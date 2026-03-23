# KARKER.IN — Integration Setup Guide

## 1. Supabase Database Schema

### Step-by-step:
1. Log into [supabase.com](https://supabase.com) → Open your project
2. Go to **SQL Editor** → **New Query**
3. Paste the entire contents of `schema.sql` and click **Run**
4. Go to **Storage** → Create bucket named `product-images` (Public: ON)
5. Done — all tables, RLS policies, and triggers are created

---

## 2. Razorpay — Payment Gateway

### Create Account
1. Go to [razorpay.com](https://razorpay.com) → **Sign Up**
2. Choose **Individual** or **Registered Business**
3. Complete KYC (Aadhaar + PAN for Individual, GST + CIN for Business)
4. KYC approval takes 2–5 business days

### Get Test Keys (Instant, no KYC needed)
1. Log in → Top-right: Switch to **Test Mode**
2. Go to **Settings** → **API Keys** → **Generate Test Key**
3. You'll get:
   - `Key ID`: starts with `rzp_test_`
   - `Key Secret`: keep this secret, never put in frontend

### Update in index.html
Search for `rzp_test_karker` and replace with your real Key ID:
```javascript
key: 'rzp_test_YOUR_ACTUAL_KEY_ID', // test mode
// For live: key: 'rzp_live_YOUR_LIVE_KEY_ID'
```

### Backend Order Creation (Required for Production)
Razorpay requires server-side order creation. Use a **Supabase Edge Function**:

1. Install Supabase CLI: `npm install -g supabase`
2. In your project folder: `supabase functions new create-order`
3. Replace contents of `supabase/functions/create-order/index.ts`:

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RAZORPAY_KEY_ID = Deno.env.get('RAZORPAY_KEY_ID')!
const RAZORPAY_KEY_SECRET = Deno.env.get('RAZORPAY_KEY_SECRET')!

serve(async (req) => {
  const { amount, currency = 'INR', receipt } = await req.json()

  const credentials = btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`)

  const response = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${credentials}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ amount, currency, receipt }),
  })

  const order = await response.json()

  return new Response(JSON.stringify(order), {
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  })
})
```

4. Set secrets:
```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxxx
supabase secrets set RAZORPAY_KEY_SECRET=your_secret_key
```
5. Deploy: `supabase functions deploy create-order`

### Razorpay Webhook (Payment Verification)
1. Razorpay Dashboard → **Webhooks** → **Add New Webhook**
2. URL: `https://YOUR_PROJECT.supabase.co/functions/v1/razorpay-webhook`
3. Events: `payment.captured`, `payment.failed`
4. Create `supabase/functions/razorpay-webhook/index.ts`:

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { createHmac } from 'https://deno.land/std@0.168.0/node/crypto.ts'

serve(async (req) => {
  const signature = req.headers.get('x-razorpay-signature')
  const body = await req.text()
  const secret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET')!

  const expectedSignature = createHmac('sha256', secret).update(body).digest('hex')
  if (signature !== expectedSignature) {
    return new Response('Invalid signature', { status: 400 })
  }

  const event = JSON.parse(body)
  if (event.event === 'payment.captured') {
    const paymentId = event.payload.payment.entity.id
    const notes = event.payload.payment.entity.notes
    // Update order status in DB
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )
    await supabase.from('orders')
      .update({ status: 'confirmed', payment_id: paymentId })
      .eq('order_number', notes.order_number)
  }

  return new Response('OK')
})
```

---

## 3. Resend — Transactional Emails

### Create Account
1. Go to [resend.com](https://resend.com) → **Sign Up** (free, 3000 emails/month)
2. **Domains** → Add your domain `karker.in`
3. Add the 3 DNS records shown to your domain registrar (GoDaddy/Namecheap/etc.)
4. Wait for verification (usually 10–30 mins)
5. Go to **API Keys** → **Create API Key** → Copy the key (starts with `re_`)

### Set Secret in Supabase
```bash
supabase secrets set RESEND_API_KEY=re_your_api_key_here
supabase secrets set FROM_EMAIL=orders@karker.in
```

### Order Confirmation Email Function
Create `supabase/functions/send-email/index.ts`:

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'orders@karker.in'

serve(async (req) => {
  const { to, type, data } = await req.json()

  let subject = '', html = ''

  if (type === 'order_confirmation') {
    subject = `Order Confirmed — #${data.order_number} | KARKER`
    html = `
      <div style="font-family:sans-serif;max-width:600px;margin:0 auto;background:#0C0B09;color:#F4F1EB;padding:40px">
        <div style="font-size:22px;font-weight:900;letter-spacing:.2em;margin-bottom:8px">KARKER</div>
        <div style="font-size:12px;color:#888;letter-spacing:.1em;margin-bottom:32px">ORDER CONFIRMED</div>
        <div style="font-size:28px;font-weight:700;margin-bottom:8px">Thanks, ${data.name}!</div>
        <div style="color:#aaa;margin-bottom:24px">Your indie pieces are on their way.</div>
        <div style="background:#181512;border:1px solid #2a2520;padding:20px;margin-bottom:24px">
          <div style="font-size:11px;letter-spacing:.12em;color:#666;margin-bottom:4px">ORDER NUMBER</div>
          <div style="font-size:20px;font-weight:700">#${data.order_number}</div>
        </div>
        <div style="background:#181512;border:1px solid #2a2520;padding:20px;margin-bottom:24px">
          <div style="font-size:11px;letter-spacing:.12em;color:#666;margin-bottom:12px">DELIVERY TO</div>
          <div>${data.address_name}</div>
          <div style="color:#aaa">${data.address_line1}, ${data.address_city}, ${data.address_state} - ${data.address_pincode}</div>
        </div>
        <div style="background:#181512;border:1px solid #2a2520;padding:20px;margin-bottom:32px">
          <div style="display:flex;justify-content:space-between">
            <span style="color:#aaa">Order Total</span>
            <span style="font-weight:700">₹${data.total}</span>
          </div>
          <div style="display:flex;justify-content:space-between;margin-top:8px">
            <span style="color:#aaa">Estimated Delivery</span>
            <span>3–5 business days</span>
          </div>
        </div>
        <div style="text-align:center;color:#555;font-size:12px">Questions? Email hello@karker.in</div>
      </div>`
  }

  if (type === 'seller_application') {
    subject = `We received your seller application — KARKER`
    html = `
      <div style="font-family:sans-serif;max-width:600px;margin:0 auto;background:#0C0B09;color:#F4F1EB;padding:40px">
        <div style="font-size:22px;font-weight:900;letter-spacing:.2em;margin-bottom:32px">KARKER</div>
        <div style="font-size:22px;font-weight:700;margin-bottom:8px">Application received, ${data.name}!</div>
        <div style="color:#aaa;line-height:1.7">
          We've received your seller application for <strong>${data.brand_name}</strong>.
          Our team will review and get back to you within 48 hours.<br><br>
          In the meantime, you can explore the seller dashboard to get familiar.
        </div>
      </div>`
  }

  if (type === 'seller_approved') {
    subject = `🎉 You're approved to sell on KARKER!`
    html = `
      <div style="font-family:sans-serif;max-width:600px;margin:0 auto;background:#0C0B09;color:#F4F1EB;padding:40px">
        <div style="font-size:22px;font-weight:900;letter-spacing:.2em;margin-bottom:32px">KARKER</div>
        <div style="font-size:22px;font-weight:700;margin-bottom:8px">You're in, ${data.name}!</div>
        <div style="color:#aaa;line-height:1.7">
          <strong>${data.brand_name}</strong> is now a verified KARKER seller.
          Log into your dashboard to start listing products and earning.
        </div>
        <a href="https://karker.in/karker_admin.html" style="display:inline-block;margin-top:24px;background:#F4F1EB;color:#0C0B09;padding:12px 28px;font-weight:700;text-decoration:none;letter-spacing:.1em">
          OPEN DASHBOARD →
        </a>
      </div>`
  }

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM_EMAIL, to, subject, html }),
  })

  return new Response(JSON.stringify(await res.json()), {
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  })
})
```

Deploy: `supabase functions deploy send-email`

### Trigger from index.html
After payment success, call:
```javascript
// In _onPaymentSuccess(), after saving order:
await fetch(`${SUPA_URL}/functions/v1/send-email`, {
  method: 'POST',
  headers: { 'Authorization': `Bearer ${SUPA_KEY}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    to: _coAddr.email,
    type: 'order_confirmation',
    data: { order_number: orderId, name: _coAddr.name, ...address, total: (total+delivery).toLocaleString('en-IN') }
  })
})
```

---

## 4. Quick Reference — Where Keys Live

| Key | Where to get it | Where to put it |
|-----|-----------------|-----------------|
| Supabase URL | Supabase → Settings → API | `index.html` line ~1974 (already set) |
| Supabase Anon Key | Supabase → Settings → API | `index.html` line ~1975 (already set) |
| Supabase Service Role Key | Supabase → Settings → API | Edge Functions only — NEVER in frontend |
| Razorpay Key ID | Razorpay → Settings → API Keys | `index.html` — search `rzp_test_karker` |
| Razorpay Key Secret | Razorpay → Settings → API Keys | Supabase Edge Function secret only |
| Resend API Key | resend.com → API Keys | Supabase Edge Function secret only |

---

## 5. Deployment Checklist

- [ ] Run `schema.sql` in Supabase SQL Editor
- [ ] Create `product-images` storage bucket (Public ON)
- [ ] Add Razorpay test keys → test checkout end-to-end
- [ ] Create Resend account + verify domain
- [ ] Deploy Edge Functions (create-order, razorpay-webhook, send-email)
- [ ] Set all Supabase secrets
- [ ] Switch Razorpay to Live mode after KYC approved
- [ ] Test a real ₹1 payment end-to-end
- [ ] Upload product images via admin panel
