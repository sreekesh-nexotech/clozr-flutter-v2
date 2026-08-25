# Webhook key — admin panel copy

Short in-panel text so users know what to do with a key. Values verified against
`public_webhooks/views.py`, `issue_views.py`, and both intake serializers.

Both tabs work identically — same auth modes, headers, limits, and error codes.
Only the URL and the accepted fields differ.

---

# Leads tab

## Panel copy

**Your endpoint**

```
POST https://dev.clozr.tech/webhooks/leads/<key_id>/
```

Post JSON to this URL and each submission becomes a lead. **Send at least
`email` or `mobile_no`** — everything else is optional.

| Field | Type | Notes |
|---|---|---|
| `email` | text, ≤140 | Required unless `mobile_no` is sent |
| `mobile_no` | text, ≤30 | Required unless `email` is sent |
| `mobile_country_code` | text, ≤10 | Prefixed onto `mobile_no` (`+91` + `9876543210` → `+919876543210`) |
| `first_name` | text, ≤140 | If omitted, derived from the email name (`ada.lovelace@…` → "Ada Lovelace"), else the phone number, else "Unknown Lead" |
| `last_name` | text, ≤140 | |
| `phone` | text, ≤30 | Secondary number |
| `phone_country_code` | text, ≤10 | Prefixed onto `phone` |
| `whatsapp_no` | text, ≤30 | |
| `whatsapp_country_code` | text, ≤10 | Prefixed onto `whatsapp_no` |
| `organization_name` | text, ≤140 | Company name |
| `website` | text, ≤140 | |
| `annual_revenue` | number | Decimal |
| `message` | text | Stored as `form.message` |
| `utm` | object | Each entry stored as `utm.<key>` — `{"source":"google","campaign":"spring"}` |
| `custom_fields` | object | Merged as-is |

Any field not listed here is kept as `form.<name>` rather than rejected, so
extra inputs on your form are safe. A country code is only prefixed when the
number doesn't already start with `+`.

```json
{
  "first_name": "Ada",
  "email": "ada@acme.com",
  "mobile_no": "9876543210",
  "mobile_country_code": "+91",
  "message": "Requesting a demo",
  "utm": { "source": "google", "campaign": "spring-sale" },
  "budget": "50k"
}
```

New leads land with the source, owner, team, and status configured on the key.

**From a browser** — list your site under Allowed origins (exact scheme and
domain, e.g. `https://acme.com`) and post from your page's JavaScript. No secret
is involved, so nothing sensitive ships to visitors.

**From your server** — sign the exact JSON body you send with the key's secret
and pass it as a header. Origins are ignored in this mode.

```
X-Signature: sha256=<HMAC-SHA256 of the raw body, hex>
```

The secret is shown only once, when the key is created or rotated. Sign the same
bytes you transmit — re-serialising the JSON after signing breaks the signature.

Returns `202` with the new `lead_id`. Every request, accepted or rejected,
appears under **Log**.

---

## Example

```js
const body = JSON.stringify({ first_name: 'Ada', email: 'ada@acme.com' });

await fetch('https://dev.clozr.tech/webhooks/leads/<key_id>/', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    // server mode only:
    'X-Signature': `sha256=${crypto.createHmac('sha256', SECRET).update(body).digest('hex')}`,
  },
  body,
});
```

---

# Tickets tab

## Panel copy

**Your endpoint**

```
POST https://dev.clozr.tech/webhooks/issues/<key_id>/
```

Post JSON to this URL and each submission becomes a ticket. **`subject` is
required** — everything else is optional.

| Field | Type | Notes |
|---|---|---|
| `subject` | text, ≤280 | **Required.** No fallback — a request without it is rejected |
| `description` | text | Full body of the report |
| `priority` | choice | `Low`, `Medium`, `High`, `Critical` — capitalised exactly |
| `reported_for` | choice | `self` or `client` |
| `customer_email` | text, ≤254 | Links to an existing customer; not stored on the ticket |
| `customer_phone` | text, ≤50 | Same — lookup only |
| `message` | text | Stored as `form.message` |
| `custom_fields` | object | Merged as-is |

Any field not listed here is kept as `form.<name>` rather than rejected.
`customer_email` / `customer_phone` only *match* an existing customer — no
customer is created. Note there is no `utm` field on tickets.

Authorisation works exactly as on the Leads tab: **From a browser** uses the
Allowed origins list, **From your server** signs the raw body with the key's
secret and sends it as `X-Signature: sha256=<hex>`.

Returns `202` with the new `issue_id`. Every request, accepted or rejected,
appears under **Log**.

**Example**

```js
const body = JSON.stringify({
  subject: 'Login fails on mobile',
  description: 'Getting a 500 after OTP entry.',
  priority: 'High',
  customer_email: 'ada@acme.com',
});

await fetch('https://dev.clozr.tech/webhooks/issues/<key_id>/', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    // server mode only:
    'X-Signature': `sha256=${crypto.createHmac('sha256', SECRET).update(body).digest('hex')}`,
  },
  body,
});
```

---

## Error codes (both tabs — for tooltips / Log column)

| Code | Meaning |
|---|---|
| 400 `invalid_payload` | Bad JSON; leads: neither `email` nor `mobile_no`; tickets: missing `subject` or a bad `priority`/`reported_for` value |
| 401 `invalid_signature` | Signature doesn't match the body sent |
| 403 `origin_not_allowed` | Origin missing from the allowlist |
| 404 `key_not_found` | Wrong, revoked, or inactive key |
| 413 `payload_too_large` | Body over 32 KB |
| 429 `rate_limited` | Over 30 requests/minute (default) |
