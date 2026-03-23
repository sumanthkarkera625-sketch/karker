-- ═══════════════════════════════════════════════════════════════
-- KARKER.IN — SUPABASE DATABASE SCHEMA
-- Run this entire file in Supabase → SQL Editor → New Query
-- ═══════════════════════════════════════════════════════════════

-- Enable UUID extension (usually already enabled on Supabase)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── PROFILES (extends Supabase auth.users) ────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name     TEXT,
  phone         TEXT,
  avatar_url    TEXT,
  role          TEXT NOT NULL DEFAULT 'buyer' CHECK (role IN ('buyer','seller','admin')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, phone)
  VALUES (NEW.id,
          COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
          COALESCE(NEW.raw_user_meta_data->>'phone', ''));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ─── SELLER PROFILES ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_profiles (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  brand_name    TEXT NOT NULL,
  handle        TEXT NOT NULL UNIQUE,    -- @stardust.fits
  bio           TEXT,
  avatar_url    TEXT,
  city          TEXT,
  instagram_url TEXT,
  aesthetic_tags TEXT[] DEFAULT '{}',   -- ['Y2K Revival', 'Indie Core']
  rating        NUMERIC(3,2) DEFAULT 0,
  total_reviews INT DEFAULT 0,
  total_products INT DEFAULT 0,
  is_verified   BOOLEAN DEFAULT FALSE,
  is_active     BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── SELLER APPLICATIONS ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_applications (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  full_name       TEXT NOT NULL,
  email           TEXT NOT NULL,
  phone           TEXT,
  brand_name      TEXT NOT NULL,
  instagram_handle TEXT NOT NULL,
  city            TEXT,
  aesthetic       TEXT,
  category        TEXT,
  bio             TEXT,
  gst_number      TEXT,
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  admin_notes     TEXT,
  applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at     TIMESTAMPTZ
);

-- ─── PRODUCTS ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.products (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  seller_id     UUID REFERENCES public.seller_profiles(id) ON DELETE SET NULL,
  name          TEXT NOT NULL,
  description   TEXT,
  price         INTEGER NOT NULL,          -- in paise (₹649 = 64900)
  mrp           INTEGER,
  category      TEXT NOT NULL,             -- 'Tops & Tees', 'Bottoms', etc.
  aesthetic     TEXT,                      -- 'Y2K Revival', 'Dark Gothic', etc.
  sizes         TEXT[] DEFAULT '{}',       -- ['XS','S','M','L','XL']
  images        TEXT[] DEFAULT '{}',       -- Array of image URLs
  emoji_icon    TEXT DEFAULT '✦',
  tag           TEXT,                      -- 'New', 'Limited', 'Sale'
  stock         INTEGER DEFAULT 50,
  is_active     BOOLEAN DEFAULT TRUE,
  is_featured   BOOLEAN DEFAULT FALSE,
  rating        NUMERIC(3,2) DEFAULT 0,
  total_reviews INT DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── PRODUCT IMAGES ────────────────────────────────────────────
-- (Supabase Storage bucket: product-images)
-- Files stored at: product-images/{seller_id}/{product_id}/{filename}
-- After creating schema, go to: Storage → New Bucket → "product-images" → Public ON

-- ─── ORDERS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.orders (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_number    TEXT NOT NULL UNIQUE,    -- KRK-XXXXXX
  user_id         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  email           TEXT,                    -- guest checkout support
  status          TEXT NOT NULL DEFAULT 'placed'
                  CHECK (status IN ('placed','confirmed','shipped','out_for_delivery','delivered','cancelled','refunded')),
  -- address snapshot
  address_name    TEXT,
  address_phone   TEXT,
  address_line1   TEXT,
  address_line2   TEXT,
  address_city    TEXT,
  address_state   TEXT,
  address_pincode TEXT,
  -- pricing
  subtotal        INTEGER NOT NULL,        -- paise
  delivery_fee    INTEGER NOT NULL DEFAULT 0,
  total           INTEGER NOT NULL,        -- paise
  -- payment
  payment_id      TEXT,                    -- Razorpay payment_id
  payment_method  TEXT,
  -- tracking
  tracking_number TEXT,
  estimated_delivery DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── ORDER ITEMS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.order_items (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id    UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id  UUID REFERENCES public.products(id) ON DELETE SET NULL,
  seller_id   UUID REFERENCES public.seller_profiles(id) ON DELETE SET NULL,
  name        TEXT NOT NULL,               -- snapshot at time of purchase
  size        TEXT,
  quantity    INTEGER NOT NULL DEFAULT 1,
  unit_price  INTEGER NOT NULL,            -- paise
  image_url   TEXT
);

-- ─── RETURNS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.returns (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id    UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reason      TEXT NOT NULL,
  description TEXT,
  status      TEXT NOT NULL DEFAULT 'requested'
              CHECK (status IN ('requested','approved','rejected','completed')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── REVIEWS ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reviews (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id  UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id    UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  rating      INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title       TEXT,
  body        TEXT,
  is_verified BOOLEAN DEFAULT FALSE,       -- verified purchase
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(product_id, user_id)
);

-- ─── WISHLISTS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wishlists (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, product_id)
);

-- ─── SITE SETTINGS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.site_settings (
  key   TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert default settings
INSERT INTO public.site_settings (key, value) VALUES
  ('announcement_bar', '"Free Delivery on orders above ₹999 · 7-Day Returns · 180+ Verified Sellers"'),
  ('drop_enabled', 'true'),
  ('maintenance_mode', 'false'),
  ('free_delivery_threshold', '999')
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.site_settings ENABLE ROW LEVEL SECURITY;

-- PROFILES
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- SELLER PROFILES (public read, owner write)
CREATE POLICY "Anyone can view active seller profiles"
  ON public.seller_profiles FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Sellers can update their own profile"
  ON public.seller_profiles FOR UPDATE USING (auth.uid() = user_id);

-- PRODUCTS (public read of active, seller write own)
CREATE POLICY "Anyone can view active products"
  ON public.products FOR SELECT USING (is_active = TRUE);
CREATE POLICY "Sellers can insert their own products"
  ON public.products FOR INSERT
  WITH CHECK (seller_id IN (SELECT id FROM public.seller_profiles WHERE user_id = auth.uid()));
CREATE POLICY "Sellers can update their own products"
  ON public.products FOR UPDATE
  USING (seller_id IN (SELECT id FROM public.seller_profiles WHERE user_id = auth.uid()));

-- ORDERS (users see own orders only)
CREATE POLICY "Users can view their own orders"
  ON public.orders FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create orders"
  ON public.orders FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- ORDER ITEMS
CREATE POLICY "Users can view their own order items"
  ON public.order_items FOR SELECT
  USING (order_id IN (SELECT id FROM public.orders WHERE user_id = auth.uid()));

-- RETURNS
CREATE POLICY "Users can view and create their own returns"
  ON public.returns FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create returns"
  ON public.returns FOR INSERT WITH CHECK (auth.uid() = user_id);

-- REVIEWS (public read, write own)
CREATE POLICY "Anyone can read reviews"
  ON public.reviews FOR SELECT USING (TRUE);
CREATE POLICY "Authenticated users can write reviews"
  ON public.reviews FOR INSERT WITH CHECK (auth.uid() = user_id);

-- WISHLISTS (private to user)
CREATE POLICY "Users can manage their own wishlist"
  ON public.wishlists FOR ALL USING (auth.uid() = user_id);

-- SITE SETTINGS (public read only — admin writes via service role)
CREATE POLICY "Anyone can read site settings"
  ON public.site_settings FOR SELECT USING (TRUE);

-- SELLER APPLICATIONS (insert only for anonymous, admin reads via service role)
CREATE POLICY "Anyone can submit a seller application"
  ON public.seller_applications FOR INSERT WITH CHECK (TRUE);

-- ═══════════════════════════════════════════════════════════════
-- SEED DATA — 24 Products across 6 categories
-- (Replace seller UUIDs with actual seller_profile IDs after creating sellers)
-- ═══════════════════════════════════════════════════════════════

-- First create a demo seller profile (run after creating an auth user)
-- INSERT INTO public.seller_profiles (brand_name, handle, bio, aesthetic_tags, is_verified, is_active)
-- VALUES ('Stardust Fits', 'stardust.fits', 'Y2K and indie fashion from Mumbai.', '{"Y2K Revival","Indie Core"}', TRUE, TRUE);

-- Sample products (update seller_id after creating above):
-- INSERT INTO public.products (name, category, aesthetic, price, mrp, sizes, images, emoji_icon, tag, is_featured, rating)
-- VALUES
--   ('Butterfly Mesh Baby Tee', 'Tops & Tees', 'Y2K Revival', 64900, 89900,
--    '{"XS","S","M","L"}',
--    '{"https://images.unsplash.com/photo-1525507119028-ed4c629a60a3?w=400&h=500&fit=crop&auto=format&q=80"}',
--    '👗', 'New', TRUE, 4.8),
--  ('more products...');

-- ═══════════════════════════════════════════════════════════════
-- STORAGE BUCKET (run separately in Supabase Dashboard → Storage)
-- ═══════════════════════════════════════════════════════════════
-- 1. Go to Storage → Create new bucket
-- 2. Name: product-images
-- 3. Public: YES (toggle ON)
-- 4. File size limit: 5MB
-- 5. Allowed MIME types: image/jpeg, image/png, image/webp
