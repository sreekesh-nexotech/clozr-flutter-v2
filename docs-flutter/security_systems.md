# Security Systems — password reset flow (frontend contract)

**What this is for:** the Settings → **Security Settings** screen. The Password card
does **not** change a password in place. There is no "current password + new
password" endpoint. The only supported path is the **email-link reset flow**
documented here, and the UI is built around it.

> TL;DR — the Password card renders a single **"Send password reset link"** button.
> Clicking it calls `POST /api/v1/auth/password-reset/` with the signed-in user's
> email. The user receives an email, clicks the link, lands on
> `/password-reset/confirm?uid=…&token=…`, and sets a new password via
> `POST /api/v1/auth/password-reset/confirm/`. Both endpoints are **public**
> (`AllowAny`) and work identically for **every** role, including System Admin and
> Executive Leadership.

**Base prefix:** `/api/v1/auth/`
**Auth:** none — both endpoints are `AllowAny`. Do **not** send `Authorization` on
them; the user is identified by the email in the body and then by the signed token.

---

## Why there is no in-place change-password

The backend exposes no endpoint that accepts `current_password` + `new_password`;
`check_password()` is not called anywhere in the codebase. Rather than build one, the
product decision is to route **all** password changes — self-service and recovery —
through the same email-verified reset. One flow, one audit trail, and possession of
the mailbox is always proven.

Practical consequences for the UI:

- The "Current password" input has no backend counterpart. Remove it.
- The user is signed out of nothing by requesting a link; the change only happens
  after they follow the email.
- The same two endpoints back both the logged-out "Forgot password?" screen and the
  logged-in Security Settings card. Only the *entry point* differs.

---

## Roles: no gating anywhere

Confirmed against source — **every** role uses the identical flow, with no special
case for admins:

| Checkpoint | Behaviour | Source |
| :--- | :--- | :--- |
| Request endpoint | `permission_classes = [AllowAny]` | [accounts/views/password_reset.py:52](../../accounts/views/password_reset.py#L52) |
| User lookup | `User.objects.get(email=email, is_active=True)` — no `is_staff`, role, or org filter | [accounts/views/password_reset.py:62](../../accounts/views/password_reset.py#L62) |
| Token | Django `default_token_generator` — user-agnostic | [accounts/views/password_reset.py:71](../../accounts/views/password_reset.py#L71) |
| Delivery | Provider-level SMTP (Resend) to `user.email`; independent of any org Gmail/OAuth integration | [emails/services/system_mail.py](../../emails/services/system_mail.py) |
| Confirm endpoint | `permission_classes = [AllowAny]` | [accounts/views/password_reset.py:100](../../accounts/views/password_reset.py#L100) |

The only conditions that block anyone are `is_active=True` and a deliverable email
address. A System Admin, an Executive Leadership user, and a CRM User all get the
same email and the same link lifetime.

---

## Endpoints

### 1. `POST /api/v1/auth/password-reset/`

Request the reset email.

**Request**
```json
{ "email": "admin@newversion.com" }
```

**Response — always `200`**
```json
{ "message": "If an account exists with this email, a password reset link has been sent." }
```

**This response is deliberately identical whether or not the account exists** — it is
anti-enumeration, not a delivery confirmation. Never render it as "email sent
successfully"; use wording like *"If that address is on file, we've sent a link."*

| Status | When |
| :--- | :--- |
| `200` | Always, on success **and** on unknown/inactive email |
| `400` | `email` missing from the body → `{"email": "This field is required."}` |
| `500` | Queueing the email raised (`APIException("Failed to send email.")`) |

**From the Security Settings card:** send the signed-in user's own email
(`GET /api/v1/auth/me/` → `email`). The endpoint does not read the JWT, so the email
must be in the body.

### 2. `POST /api/v1/auth/password-reset/confirm/`

Set the new password using the emailed token.

**Request**
```json
{ "uid": "<from the link query string>",
  "token": "<from the link query string>",
  "password": "NewP@ssw0rd" }
```

**Response — `200`**
```json
{ "message": "Password has been reset successfully." }
```

| Status | When |
| :--- | :--- |
| `200` | Password updated |
| `400` | Any of `uid`/`token`/`password` missing → `"UID, token, and password are required."` |
| `400` | `uid` undecodable or user not found/inactive → `"Invalid link."` |
| `400` | Token expired or already used → `"Invalid or expired token."` |
| `400` | Password fails the org policy → the validator's message (see below) |

All four `400` bodies are a bare string in DRF's standard error shape — surface the
message directly.

---

## The reset link

Built at [accounts/views/password_reset.py:75-76](../../accounts/views/password_reset.py#L75-L76):

```
{FRONTEND_URL}/password-reset/confirm?uid=<uidb64>&token=<token>
```

`FRONTEND_URL` comes from env (`nexocrm/settings.py:360`, default
`http://localhost:3000`). **The frontend must serve a route at
`/password-reset/confirm`** that reads `uid` and `token` from the query string and
POSTs them back with the new password.

**Lifetime: 24 hours.** `PASSWORD_RESET_TIMEOUT = 86400` (`nexocrm/settings.py:363`),
matching the "expire in 24 hour(s)" line in the email body. (The
`PasswordResetView` docstring still says "1 hour" — that comment is stale; the
setting is authoritative.)

Tokens are single-use in effect: `default_token_generator` keys off the password hash
and `last_login`, so a used link stops validating.

---

## Password policy (validate client-side to match)

The new password is checked against the **organization's** policy by
`PasswordStrengthValidator` ([accounts/validators.py](../../accounts/validators.py)),
read from `Organization.settings["security_policy"]`:

| Key | Default | Error message on failure |
| :--- | :--- | :--- |
| `min_password_length` | `8` | `This password must contain at least N characters.` |
| `require_uppercase` | `true` | `This password must contain at least one uppercase letter.` |
| `require_lowercase` | `true` | `This password must contain at least one lowercase letter.` |
| `require_numbers` | `true` | `This password must contain at least one number.` |
| `require_special_chars` | `true` | `This password must contain at least one special character.` (regex `[\W_]`) |

Admins read and edit these at `GET|PUT|PATCH /api/v1/settings/security/policy/`
(gated by the `settings` module permission). The reset-confirm screen is
**unauthenticated**, so it cannot fetch the policy — either hard-code the defaults as
client-side hints or rely on the server's `400` message. The server is the
authority either way.

---

## Side effects on a successful reset

Fires in [accounts/views/password_reset.py:129-157](../../accounts/views/password_reset.py#L129-L157):

1. `user.set_password(password)` + save.
2. **Permission-cache bump** — `increment_cache_version(f"user:{user_id}")`.
3. **Audit log** — an `AuditLog` row with `action="password_reset"`, capturing IP and
   user agent. Written **asynchronously by the Celery worker**; a dead worker means
   no audit row.
4. **In-app / push notification** — a `PasswordChanged` notification to the user.
   Wrapped in try/except; never blocks the reset.

### What does *not* happen

**Existing sessions are not terminated.** The method that runs here is named
`_invalidate_user_tokens` ([line 161](../../accounts/views/password_reset.py#L161))
but it only bumps the permission cache — it does not blacklist JWTs or deactivate
`UserSession` rows. **After a password reset, every previously issued access token
keeps working until it expires (up to 30 minutes), on every device.**

Do not tell the user "you've been signed out everywhere." If that guarantee is
wanted, it needs a separate fix — see *Known gaps*.

---

## Operational dependency: Celery

`send_password_reset_email` calls `send_onboarding_email.delay(...)`
([accounts/views/password_reset.py:42](../../accounts/views/password_reset.py#L42)) —
delivery is queued, not synchronous. **The view returns `200` whether or not the
worker is alive.**

So "user requested a reset and no email arrived" is almost always a **dead Celery
worker**, not a bug in the reset code — the same failure mode that silently drops
audit-log rows. Check the worker before debugging this flow.

The task retries with exponential backoff on transient SMTP errors and gives up on
permanent ones (unverified domain, invalid recipient, auth failure), logging in both
cases ([accounts/tasks.py:25-62](../../accounts/tasks.py#L25-L62)).

---

## Suggested UI copy

Password card, replacing the current/new inputs:

> **Password**
> For your security, password changes are confirmed by email.
> `[ Send password reset link ]`

After the `200`:

> If **admin@newversion.com** is on file, we've sent a reset link. It expires in 24
> hours. Didn't get it? Check spam, then try again.

Rate-limit the button client-side (e.g. 60s cooldown) — the endpoint itself is not
rate-limited, unlike `/auth/login/`.

---

## Related endpoints

- `GET /api/v1/auth/me/` — the signed-in user's profile; source of the `email` to POST.
- `POST /api/v1/auth/logout/` — blacklists a **refresh** token. Pair with the reset
  card if you want the current device signed out after a change. Note it does not
  mark the `UserSession` row inactive.
- `POST /api/v1/auth/activate-account/confirm/` — the same uid+token pattern, used to
  set the *initial* password on a new account.
- `PATCH /api/v1/management/users/<user_id>/` — lets an admin set **another** user's
  password directly ([management/serializers/user.py:259](../../management/serializers/user.py#L259)).
  Admin tooling only; not part of this screen.
- `GET|PUT|PATCH /api/v1/settings/security/policy/` — read/write the org password policy.

DEBUG-only: `/reset-password/<uidb64>/<token>/` renders a server-side test form
(`nexocrm/urls.py:71-75`), 404s when `DEBUG=False`. Useful for testing the flow
without the frontend.

---

## Known gaps (rest of the Security Settings screen)

Documented so the UI isn't built on promises the backend doesn't keep. None of these
affect the reset flow above.

| Card | Status |
| :--- | :--- |
| **Password** | ✅ Works as documented here (email-link only). |
| **Two-factor authentication** | ✅ Real TOTP 2FA — see [Two-factor authentication (TOTP)](#two-factor-authentication-totp) below. |
| **Login alerts** | ❌ No backend at all — no model, signal, template, or preference field. |
| **IP allow-list** | ⚠️ Enforced at login and per-request, but `ip_whitelist`/`ip_blacklist` are exact-match `IPAddressField` lists — **CIDR ranges are not supported** despite the "office IP ranges" copy. |
| **Active sessions** | ⚠️ List works (`GET /api/v1/settings/security/sessions/`). **Revoke does not actually revoke:** `UserSession.jti` holds the *access*-token JTI, but SimpleJWT only creates `OutstandingToken` rows for *refresh* tokens, so the blacklist call is a silent no-op and the middleware passes through inactive sessions. A revoked session stays usable until the token expires. No geolocation on the model. |

Sessions and the security policy are additionally gated behind
`HasSettingsPermission` (the `settings` module permission), so a CRM User currently
**cannot** view their own sessions — a per-user action sitting behind an admin gate.
2FA is deliberately **not** gated this way (see below).

There are no tests for the security policy or sessions.

---

## Two-factor authentication (TOTP)

**What this is for:** the Settings → Security Settings → **Two-factor authentication**
card, plus the mandatory-enrolment flow when an org turns on `require_2fa`.

**Base prefix:** `/api/v1/auth/` — deliberately *not* under `/settings/`, so it can't
be re-gated behind `HasSettingsPermission` by reflex. 2FA is a per-user authentication
concern; every user (CRM/PMO/System Admin alike) manages their own.

### Self-serve enrolment (authenticated, `IsAuthenticated`)

| Method | Path | Notes |
| :--- | :--- | :--- |
| POST | `/auth/2fa/enrol/start/` | Returns `{secret, provisioning_uri, issuer}`. `provisioning_uri` is an `otpauth://` URI — render it as a QR code client-side (no server-side QR image; avoids adding an image-generation dependency). 409 if already confirmed. |
| POST | `/auth/2fa/enrol/confirm/` | Body: `{code}`. Verifies the code, marks the device confirmed, returns `{detail, backup_codes: [...]}` — **the only time the 10 backup codes are shown.** |
| GET | `/auth/2fa/status/` | `{enabled, confirmed_at, backup_codes_remaining, required_by_organization}`. Not cached — reflects state immediately after enrol/disable/regenerate. |
| POST | `/auth/2fa/disable/` | Body: `{password, code}` — **both required.** 403 if `require_2fa` is on for the org (cannot self-disable a mandated second factor). |
| POST | `/auth/2fa/backup-codes/regenerate/` | Body: `{password, code}` — `code` must be a **TOTP** code, not a backup code (a stolen backup-code printout can't mint a fresh set). Returns 10 new codes; invalidates the old set. |

### Login-time (public, `AllowAny`)

| Method | Path | Notes |
| :--- | :--- | :--- |
| POST | `/auth/login/2fa/` | Body: `{challenge_token, code}` — `code` is a TOTP or backup code. Returns the normal login body (`access_token`/`refresh_token`/`user`), plus `backup_codes_remaining` if a backup code was used. |
| POST | `/auth/login/2fa/enrol/start/` | Body: `{enrolment_token}` — forced-enrolment variant of `2fa/enrol/start/` for a user who has no device yet but whose org requires one. |
| POST | `/auth/login/2fa/enrol/confirm/` | Body: `{enrolment_token, code}` — confirms and, unlike the self-serve version, also returns real JWTs (the user had no session yet). |

### The three post-login-credentials branches

`POST /auth/login/` (unchanged path) now returns one of three shapes, all HTTP 200,
depending on the user's enrolment state and the org's `require_2fa` flag
(`Organization.settings["security_policy"]["require_2fa"]`, PATCH via
`/settings/security/policy/`):

1. **No device, not required** — unchanged: `{access_token, refresh_token, user}`.
   Every existing caller of the login endpoint keeps working untouched.
2. **Confirmed device exists** (required or not — an existing device is never waived):
   `{two_factor_required: true, challenge_token, expires_in: 300, methods: ["totp", "backup_code"], user: {id, email}}`.
3. **No device, but the org requires one**:
   `{two_factor_setup_required: true, enrolment_token, expires_in: 900, message}`.

No `access_token` is present in branches 2/3 — no `UserSession` is created and
`last_login`/`LoginAttempt` success bookkeeping is deferred until the second factor
actually clears (see `accounts/services/two_factor.py::evaluate_login_second_factor`
and `accounts/services/session.py::finalize_login`).

### Security properties worth knowing

- **Challenge/enrolment tokens are signed (`django.core.signing`), not JWTs** — they
  cannot be used as `Authorization: Bearer` credentials (wrong format, wrong key,
  namespaced by salt+purpose). They only ever travel in a request body.
- **The challenge token is single-use**; the **enrolment token is not** — it is
  legitimately presented to two separate endpoints in sequence (`enrol/start` then
  `enrol/confirm`), so its security is signature + 15-minute expiry + purpose
  namespacing, not a consumed nonce.
- **Replay protection**: each TOTP code can be accepted at most once — the device
  tracks `last_used_counter` and rejects any code at or before it, even a code that
  would otherwise still be inside the ±30s valid window.
- **Lockout** is shared across TOTP and backup-code attempts (an attacker can't get 5
  guesses of each), keyed in Redis, reusing the org's existing `max_login_attempts` /
  `lock_duration_minutes` from `security_policy` — no new admin-facing knobs.
- **Superusers are not exempt** — the sole System Admin is the account most worth
  protecting.
- **Backup codes** are hashed with sha256 + `hmac.compare_digest` (not Argon2/
  `make_password`) — they're high-entropy machine-generated secrets, not human-chosen
  passwords, so slow hashing buys no offline-brute-force benefit and only adds memory
  cost on a pre-auth endpoint.
- **Known gap:** there is no admin-assisted recovery if a sole System Admin loses both
  their authenticator and all backup codes. Don't turn on `require_2fa` for a
  single-admin org without a support-verified recovery plan in place.
- **Mobile:** the Flutter client is out-of-repo and does not yet handle the new
  challenge/enrolment response shapes. Keep `require_2fa` **off** for any org with
  mobile users until that ships — the default is `false`, so nothing changes unless
  an admin opts in via `PATCH /settings/security/policy/`.

---

## Updating the login screen for 2FA (frontend contract)

**This is the part that requires a code change, not just awareness.** Today the
login screen almost certainly does:

```js
const res = await api.post('/auth/login/', { email, password });
setTokens(res.data.access_token, res.data.refresh_token);
navigate('/dashboard');
```

That still works for the majority of users (no device enrolled, org doesn't require
one) — **but it will silently break for anyone with 2FA on**, because
`res.data.access_token` won't exist. The fix is to branch on which of three shapes
came back, all as HTTP `200`:

### Step 1 — branch on the response shape

```js
const res = await api.post('/auth/login/', { email, password });

if (res.data.access_token) {
  // Shape 1: no 2FA in play. Unchanged — existing code path.
  setTokens(res.data.access_token, res.data.refresh_token);
  navigate('/dashboard');

} else if (res.data.two_factor_required) {
  // Shape 2: user has a confirmed device. Show the code-entry screen.
  showTwoFactorPrompt({
    challengeToken: res.data.challenge_token,
    methods: res.data.methods,          // ["totp", "backup_code"]
    expiresIn: res.data.expires_in,      // 300 seconds — start a countdown
  });

} else if (res.data.two_factor_setup_required) {
  // Shape 3: org requires 2FA and this user has no device yet. Force enrolment.
  showForcedEnrolment({
    enrolmentToken: res.data.enrolment_token,
    expiresIn: res.data.expires_in,      // 900 seconds
    message: res.data.message,
  });
}
```

`res.data.user` in shapes 2/3 is intentionally minimal (`{id, email}` only) — don't
expect org/role data until after the second factor clears.

### Step 2a — the code-entry screen (`two_factor_required`)

A single input for a 6-digit code (also accepts a backup code — same field, no UI
distinction needed since the server tries both):

```js
const res = await api.post('/auth/login/2fa/', {
  challenge_token: challengeToken,   // from step 1, unmodified
  code: userInput,                   // "123456" or a backup code like "ABCDE-FGHJK"
});

if (res.status === 200) {
  setTokens(res.data.access_token, res.data.refresh_token);
  if (res.data.backup_codes_remaining !== undefined) {
    // A backup code was used instead of a TOTP code — surface this,
    // e.g. "8 backup codes remaining" so the user notices they're running low.
  }
  navigate('/dashboard');
}
```

Error handling:

| Status | Body | What it means | UI |
| :--- | :--- | :--- | :--- |
| `400` | `{"detail": "Invalid code."}` | Wrong code | "Incorrect code, try again." Let them retry. |
| `400` | `{"detail": "Invalid or expired challenge."}` | `challenge_token` expired (5 min) or already used | Send them back to step 1 — re-submit email+password. |
| `429` | `{"detail": "Too many failed attempts..."}` | Shared TOTP+backup-code lockout tripped | "Too many attempts. Try again in a few minutes." Don't offer an immediate retry button. |

**Do not** attempt to reuse a `challenge_token` after any response (success or
failure-then-retry-elsewhere) — it's single-use. If the user needs to try again from
scratch, that means calling `/auth/login/` again, not resubmitting the same token.

### Step 2b — forced enrolment screen (`two_factor_setup_required`)

Same QR-scan-then-confirm UI as the self-serve Settings flow, just fed by different
endpoints and the `enrolment_token` from step 1 instead of an auth header:

```js
// Show the QR immediately — no extra "start" call needed if you already have
// enrolment_token, but the server still requires calling start/ to actually
// generate the secret:
const start = await api.post('/auth/login/2fa/enrol/start/', {
  enrolment_token: enrolmentToken,
});
renderQrCode(start.data.provisioning_uri);   // otpauth://... — render as QR client-side
showManualEntryCode(start.data.secret);       // fallback if they can't scan

// User scans, types the 6-digit code showing on their app:
const confirm = await api.post('/auth/login/2fa/enrol/confirm/', {
  enrolment_token: enrolmentToken,   // same token, reused — this one is NOT single-use
  code: userInput,
});

if (confirm.status === 200) {
  setTokens(confirm.data.access_token, confirm.data.refresh_token);
  showBackupCodesOnceModal(confirm.data.backup_codes);  // 10 codes — force an
                                                          // explicit "I've saved these"
                                                          // acknowledgment before continuing
  navigate('/dashboard');
}
```

Note the asymmetry: `enrolment_token` **is reused** across the `start` and `confirm`
calls (it's valid for the full 15-minute window across both), unlike the
single-use `challenge_token` in step 2a.

### State machine summary

```
POST /auth/login/
      │
      ├─ access_token present ─────────────────────────────▶ done, logged in
      │
      ├─ two_factor_required ──▶ show code prompt
      │        │
      │        └─ POST /auth/login/2fa/ {challenge_token, code}
      │                 ├─ 200 ─────────────────────────────▶ done, logged in
      │                 ├─ 400 invalid code ─────────────────▶ retry same screen
      │                 ├─ 400 expired/used token ────────────▶ back to /auth/login/
      │                 └─ 429 locked out ────────────────────▶ cool-down message
      │
      └─ two_factor_setup_required ──▶ show forced-enrolment (QR) screen
               │
               ├─ POST /auth/login/2fa/enrol/start/ {enrolment_token} ──▶ render QR
               └─ POST /auth/login/2fa/enrol/confirm/ {enrolment_token, code}
                        ├─ 200 ─▶ show backup codes once, then done, logged in
                        └─ 400 invalid code ─▶ retry same screen (same enrolment_token)
```

### Checklist for the frontend PR

- [ ] Login screen branches on `access_token` / `two_factor_required` /
      `two_factor_setup_required` — not just `access_token`.
- [ ] A code-entry screen exists, accepting either a 6-digit TOTP code or a
      formatted backup code in the same input.
- [ ] A QR-render step exists for forced enrolment (reuse whatever component the
      Settings → Security → 2FA card already uses for self-serve enrolment, if built).
- [ ] Backup codes are shown **exactly once**, with an explicit "I've saved these"
      confirmation before proceeding — they cannot be retrieved again short of
      regenerating (which invalidates the old set).
- [ ] `challenge_token` is treated as single-use and thrown away after one
      `/auth/login/2fa/` call, success or failure.
- [ ] A `429` from `/auth/login/2fa/` shows a cool-down message, not an immediate
      retry button.
- [ ] Every existing "check `res.data.access_token`" call site elsewhere in the app
      (not just the login screen) is audited — anywhere that assumes `/auth/login/`
      always returns tokens synchronously needs the same three-way branch.
