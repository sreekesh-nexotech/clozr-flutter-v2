# Login & Two-Factor Authentication — API Guide

Covers credential login, JWT refresh/logout, password reset, account
activation, and the full TOTP-based two-factor authentication (2FA) flow —
both self-serve (settings) and login-time (forced/voluntary) variants.

All routes are under `/api/v1/auth/`. Login-time 2FA endpoints (`login/2fa/*`)
are `AllowAny` — they authenticate via a short-lived signed token in the body,
never a bearer `Authorization` header, since the caller doesn't have a real
JWT yet at that point in the flow.

---

## 1. Login — `POST /login/`

```
POST /api/v1/auth/login/
{ "email": "user@example.com", "password": "..." }
```

Rate-limited 10/min per IP. Enforces org-configurable account lockout
(`security_policy.max_login_attempts`, default 5 failed attempts / 60 min
lock — `security_policy.lock_duration_minutes`) and IP allow/block lists
(`security_policy.ip_whitelist` / `ip_blacklist`). A locked account gets
`429` (via DRF `Throttled`) with a message telling the user when to retry or
to reset their password.

The response shape depends on whether the account has 2FA — **check for
`access_token` in the response to know which case you're in**; only its
presence means login is actually complete.

### 1a. No 2FA — `200`

```json
{
  "access_token": "<JWT>",
  "refresh_token": "<JWT>",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "full_name": "Jane Doe",
    "organizations": [
      { "id": "uuid", "name": "Acme Co", "subdomain": "acme", "is_primary": true }
    ]
  }
}
```

### 1b. 2FA already enabled on the account — `200`, login NOT yet complete

No tokens are issued at this step — go to §2.

```json
{
  "two_factor_required": true,
  "challenge_token": "<opaque signed token, 5 min TTL>",
  "expires_in": 300,
  "methods": ["totp", "backup_code"],
  "user": { "id": "uuid", "email": "user@example.com" }
}
```

### 1c. Org requires 2FA but this account hasn't enrolled yet — `200`, login NOT yet complete

No tokens are issued at this step — go to §3 (forced enrolment).

```json
{
  "two_factor_setup_required": true,
  "enrolment_token": "<opaque signed token, 15 min TTL>",
  "expires_in": 900,
  "message": "Your organization requires two-factor authentication. Please set it up to continue."
}
```

Notes:
- A confirmed device is **never waived** by the org's `require_2fa` flag —
  that flag only controls mandatory *enrolment*. Superusers are **not**
  exempt from either branch.
- `challenge_token` / `enrolment_token` are signed (`django.core.signing`),
  not JWTs — they cannot be used as a bearer credential, only ever travel in
  the request body, and are scoped to a single `purpose`. `challenge_token`
  is single-use (replay-protected via a cache nonce); `enrolment_token` is
  reusable across its two enrolment calls (§3) within its 15-minute TTL.
- A failed-login attempt (bad password) is recorded toward the lockout
  counter immediately. A password-only success that lands in 1b/1c is **not**
  recorded as a successful attempt — only clearing the second factor counts,
  so a password-only attacker can't reset the lockout counter without it.

---

## 2. Verify 2FA at login — `POST /login/2fa/`

For the 1b branch (device already enrolled). `AllowAny`, rate-limited 10/min
per IP.

```
POST /api/v1/auth/login/2fa/
{ "challenge_token": "<from 1b>", "code": "123456" }
```

`code` accepts either a live TOTP code or one of the account's unused backup
codes — both count against the same shared lockout counter (org's
`max_login_attempts`/`lock_duration_minutes`), so an attacker can't get N
guesses against each independently.

**200** — same shape as §1a (`access_token`, `refresh_token`, `user`). This is
the point real JWTs are actually minted and the `UserSession` row is created
— nothing before this step counts as a completed login. If a backup code was
used instead of a TOTP code, the response also includes:

```json
{ "...": "...", "backup_codes_remaining": 7 }
```

Errors: `400` invalid/expired `challenge_token`; `400` invalid code;
`429` too many failed attempts (lockout).

---

## 3. Forced enrolment at login — `login/2fa/enrol/start/` + `login/2fa/enrol/confirm/`

For the 1c branch (org requires 2FA, account has no device yet). Both
`AllowAny`, rate-limited 10/min per IP, and both take the `enrolment_token`
from 1c — this pair is the login-time equivalent of the self-serve enrolment
in §4, wired for a user who doesn't have a JWT yet.

### 3a. `POST /login/2fa/enrol/start/`

```
{ "enrolment_token": "<from 1c>" }
```

**200**:
```json
{
  "secret": "BASE32SECRET...",
  "provisioning_uri": "otpauth://totp/NexoCRM:user@example.com?secret=...&issuer=NexoCRM",
  "issuer": "Acme Co"
}
```
Render `provisioning_uri` as a QR code (or show `secret` for manual entry) in
an authenticator app.

### 3b. `POST /login/2fa/enrol/confirm/`

```
{ "enrolment_token": "<same token>", "code": "123456" }
```

Verifies the first TOTP code from the newly-added authenticator entry,
confirms the device, generates backup codes, and — unlike self-serve
confirm — **also finishes login**, issuing real JWTs directly:

**200**:
```json
{
  "access_token": "<JWT>",
  "refresh_token": "<JWT>",
  "user": { "...": "..." },
  "backup_codes": ["ABCD-1234", "..."]
}
```

`backup_codes` are shown **once**, in plaintext — only hashes are persisted.
Prompt the user to save them before navigating away.

---

## 4. Self-serve 2FA management (authenticated)

Under `/api/v1/auth/2fa/*`, `IsAuthenticated` (not `/settings/` — deliberately
kept as an auth concern available to every user, not admin-gated). Use these
from an account-security screen once the user is already logged in.

### 4a. `GET /2fa/status/`

```json
{
  "enabled": true,
  "confirmed_at": "2026-05-01T10:00:00Z",
  "backup_codes_remaining": 8,
  "required_by_organization": false
}
```
Not cached — reflects state changed by the very actions below.

### 4b. Enrol — `POST /2fa/enrol/start/` then `POST /2fa/enrol/confirm/`

Same request/response shapes as §3a/§3b, except:
- `enrol/start/` takes no body (uses `request.user`); `409` if a confirmed
  device already exists.
- `enrol/confirm/` takes just `{ "code": "123456" }` (no token — the user is
  already authenticated) and does **not** issue new JWTs; response is
  `{ "detail": "Two-factor authentication enabled successfully.", "backup_codes": [...] }`.

### 4c. `POST /2fa/disable/`

Requires **both** password and a current OTP — a stolen access token alone
cannot remove the second factor:

```json
{ "password": "...", "code": "123456" }
```

`403` if the org's `security_policy.require_2fa` is on (cannot self-disable
a mandatory factor). `403` on wrong password, `400` on wrong code or if 2FA
isn't enabled. `200 { "detail": "Two-factor authentication disabled." }` on
success.

### 4d. `POST /2fa/backup-codes/regenerate/`

Same `{ "password", "code" }` body as disable. **Rejects a backup code as the
verification factor** — only a live TOTP code is accepted here, so a stolen
printout of old codes can't be used to mint a fresh set and lock the real
user out. `200 { "backup_codes": [...] }` (new set; old ones invalidated).

All 2FA state changes (`enrolled`, `disabled`, `backup_code_used`) are
recorded to the audit log asynchronously (fire-and-forget — see
`docs/working/audit-log-async-worker-dependency.md`).

---

## 5. Token refresh — `POST /login/refresh/`

```json
{ "refresh": "<refresh JWT>" }
```
**200** `{ "access": "<new access JWT>" }`. Standard SimpleJWT behavior — no
custom logic layered on top.

## 6. Logout — `POST /logout/`

`IsAuthenticated`, rate-limited 10/min per IP.

```json
{ "refresh": "<refresh JWT>" }
```
Blacklists the refresh token. `200 { "message": "Successfully logged out." }`;
`400` if the token is missing/invalid. Does not affect the `UserSession` row
directly — that's a separate `settings` concept from session limiting (see
`finalize_login`, `docs/apis/...` session/device management docs if present).

## 7. Current user — `GET /me/` and `GET /me/modules/`

Both `IsAuthenticated`, rate-limited 60/min per user, cached 5 min
(user+org-scoped).

- `GET /me/` — full `User` serializer (profile, org, etc).
- `GET /me/modules/` — the sidebar/module-access map (`is_staff`/superuser get
  everything; Executive Leadership and staff always get Settings + Dashboard;
  everyone else gets their OR-merged role grants). See
  `docs/working/permissions.md`.

---

## 8. Password reset (forgot password, not logged in)

Both `AllowAny`.

### `POST /password-reset/`
```json
{ "email": "user@example.com" }
```
Always `200` with the same generic message, whether or not the email exists
— avoids account enumeration:
```json
{ "message": "If an account exists with this email, a password reset link has been sent." }
```
Sends a link (`{FRONTEND_URL}/password-reset/confirm?uid=...&token=...`) via
email (Celery-queued, Django's `default_token_generator`, 24h validity by
convention though not server-enforced beyond the token's own expiry).

### `POST /password-reset/confirm/`
```json
{ "uid": "...", "token": "...", "password": "newpassword" }
```
Validates the new password against the org's password policy
(`security_policy` on `Organization.settings`). On success: sets the new
password, invalidates cached permissions for the user, writes an audit log
entry, and sends a "password changed" notification. `200
{ "message": "Password has been reset successfully." }`. `400` for an
invalid/expired token/link or a policy-violating password.

---

## 9. Account activation (new user's first login)

### `POST /activate-account/confirm/`
`AllowAny`. Sets the initial password and activates a newly-created (invited)
account — only works while `is_active=False`:
```json
{ "uid": "...", "token": "...", "password": "newpassword" }
```
`200 { "message": "Account activated successfully. You can now log in." }`
on success, then proceed to §1 (login).

### `POST /activate-account/resend/`
Admin-only (`create_user` permission). Resends the activation email for an
inactive user in the caller's org:
```json
{ "email": "user@example.com" }
```
or `{ "user_id": "uuid" }`. `200 { "message": "Activation email resent to ..." }`;
`404` if no matching inactive user exists in the org.

---

## Flow summary

```
POST /login/ ──┬─ access_token present ─────────────────────────► logged in
               │
               ├─ two_factor_required=true ──► POST /login/2fa/ ─► logged in
               │        (challenge_token)         (code)
               │
               └─ two_factor_setup_required=true
                        (enrolment_token)
                                │
                                ▼
                  POST /login/2fa/enrol/start/  (scan QR)
                                │
                                ▼
                  POST /login/2fa/enrol/confirm/ (code) ────────► logged in
                                                                  (+ backup_codes)
```
