# Two-Factor Authentication (TOTP) — how it works

**What this is for:** a standalone reference for the TOTP-based 2FA system —
what it does, how a user turns it on and uses it, and how a developer extends
or debugs it. Self-contained; you shouldn't need to read the code to
understand the feature from this doc alone.

For the frontend contract of the *password reset* flow (a related but
separate part of the Security Settings screen), see
[security_systems.md](security_systems.md).

---

## 1. What it is, in one paragraph

Each user can attach a TOTP ("Time-based One-Time Password") authenticator —
Google Authenticator, Authy, 1Password, etc. — to their account as a second
login factor. Once attached, logging in with the correct password is no
longer enough: the server also asks for a live 6-digit code (or, if the
phone is lost, a one-time backup code) before issuing real access. Nothing
is emailed or texted — the whole exchange is a shared secret established
once at enrolment time, after which the server and the authenticator app
compute matching codes independently, in sync only via clock.

An organization can also **require** every member to have 2FA enabled
(`require_2fa`); anyone without a device is walked through mandatory
enrolment the moment they try to log in, rather than being locked out.

---

## 2. For end users

### Turning it on

1. Open **Settings → Security Settings → Two-factor authentication** and
   start enrolment.
2. The screen shows a QR code. Scan it with an authenticator app (Google
   Authenticator, Authy, 1Password, Microsoft Authenticator — any standard
   TOTP app works). Can't scan? A manual entry code is shown alongside the
   QR for typing the secret in by hand.
3. The app immediately starts showing a rotating 6-digit code. Type the
   current code into the confirmation box.
4. On success, you're shown **10 backup codes** — save these somewhere safe
   (password manager, printed copy). **This is the only time they're ever
   shown.** They're for the one situation TOTP can't handle: you don't have
   your phone.

From this point on, every login asks for a code from your app after your
password.

### Logging in

1. Enter email + password as usual.
2. You'll be asked for a **6-digit code** from your authenticator app. Enter
   it and you're in.
3. **Lost your phone?** Use one of your 10 backup codes instead of the
   6-digit code — same input box, same flow. Each backup code works exactly
   once; using one leaves you with 9 remaining (shown after successful
   login, and any time on the Security Settings screen).

### If your organization requires 2FA

If an admin has turned on mandatory 2FA for your organization and you
haven't enrolled yet, logging in walks you straight into the QR-scan +
confirm flow described above — you can't get further until you finish it.
Nobody is locked out by turning this flag on; unenrolled users are just
redirected into enrolment instead of being let straight in.

### Turning it off

Settings → Security Settings → Two-factor authentication → Disable. You'll
need your **current password and a live code from your app** — a stolen
session token alone can't turn this off. If your org requires 2FA, you
can't disable it at all (the button is blocked with an explanation).

### Losing both your phone and your backup codes

There is currently **no self-service recovery** for this. Contact a System
Admin — see the developer note on admin recovery below, since there's no
built-in tool for this yet either. **If you're the only System Admin in
your organization, do not lose both your phone and your backup codes** —
plan for this before turning 2FA on for yourself.

---

## 3. For developers

### Where the code lives

| Piece | File |
| :--- | :--- |
| Device model (secret, backup codes, replay counter) | `accounts/models/totp_device.py` |
| TOTP verify / backup-code logic | `accounts/services/totp.py` |
| Challenge/enrolment tokens, lockout, login gate | `accounts/services/two_factor.py` |
| Session creation, shared by all login-success paths | `accounts/services/session.py` |
| Login serializer (the gate itself) | `accounts/serializers/token.py` |
| The 8 HTTP endpoints | `accounts/views/two_factor.py`, `accounts/urls.py` |
| Org-level `require_2fa` flag | `settings/serializers.py` (`SecurityPolicySerializer`), read via `Organization.settings["security_policy"]["require_2fa"]` |
| Fernet encryption helpers | `nexocrm/crypto.py` |
| Tests | `accounts/tests/test_two_factor.py` (endpoints), `accounts/tests/test_two_factor_login.py` (login flow) |

### The request flow

```
POST /auth/login/                      (unchanged URL)
        │
        ▼
  password correct?  ──No──▶ 401, LoginAttempt failure recorded
        │ Yes
        ▼
  evaluate_login_second_factor(user)
        │
        ├── no device, require_2fa off  ─▶ unchanged response:
        │                                   {access_token, refresh_token, user}
        │
        ├── confirmed device exists     ─▶ {two_factor_required: true,
        │   (required or not — an                challenge_token, expires_in: 300,
        │    existing device is never             methods: ["totp","backup_code"],
        │    waived by the org flag)              user: {id, email}}
        │
        └── no device, require_2fa on   ─▶ {two_factor_setup_required: true,
                                              enrolment_token, expires_in: 900,
                                              message}
```

No `access_token` appears in the second or third branch. `UserSession`
creation, `last_login` stamping, and `LoginAttempt` success recording are
all deferred until the second factor actually clears — see
`accounts/services/session.py::finalize_login`, called from exactly three
places: the unchanged single-factor path, `POST /auth/login/2fa/` (E3), and
`POST /auth/login/2fa/enrol/confirm/` (E5).

### All 8 endpoints

| # | Method | Path | Auth | Purpose |
| :-- | :-- | :-- | :-- | :-- |
| E1 | POST | `/auth/2fa/enrol/start/` | authenticated | Generate secret + QR URI |
| E2 | POST | `/auth/2fa/enrol/confirm/` | authenticated | Confirm code, get 10 backup codes |
| E3 | POST | `/auth/login/2fa/` | public | Submit code against a `challenge_token`, get real JWTs |
| E4 | POST | `/auth/login/2fa/enrol/start/` | public | Same as E1, but keyed by `enrolment_token` |
| E5 | POST | `/auth/login/2fa/enrol/confirm/` | public | Same as E2, but also issues JWTs (first successful login) |
| E6 | GET | `/auth/2fa/status/` | authenticated | `{enabled, confirmed_at, backup_codes_remaining, required_by_organization}` |
| E7 | POST | `/auth/2fa/disable/` | authenticated | Requires `{password, code}`; blocked if org requires 2FA |
| E8 | POST | `/auth/2fa/backup-codes/regenerate/` | authenticated | Requires `{password, code}` (TOTP only, not a backup code) |

All of these live under `/api/v1/auth/`, not `/api/v1/settings/` —
deliberate, so nobody re-adds `HasSettingsPermission` by reflex. 2FA is a
per-user authentication concern, not an admin-gated setting; every role
(including a plain CRM User) manages their own device. Only the
**`require_2fa` flag itself** is org-admin territory, via the existing
`GET|PATCH /api/v1/settings/security/policy/`.

### Security mechanisms, and why they're built this way

- **Challenge/enrolment tokens are signed (`django.core.signing`), not
  JWTs.** Minting one costs zero DB queries — appropriate since login is the
  hottest path in the system. They cannot be used as `Authorization: Bearer`
  credentials: wrong token format (not a 3-segment JWS), wrong signing key
  (`SECRET_KEY`, not the RS256 key backing real JWTs), and salt-namespaced by
  purpose so a challenge token doesn't even parse under the enrolment salt.
- **The challenge token is single-use** (an atomic cache `add()` on its
  embedded nonce burns it on first read). **The enrolment token is not** —
  it's deliberately presented to two sequential endpoints (`enrol/start`
  then `enrol/confirm`), so its security comes from the signature + 15-minute
  expiry + purpose check, not a consumed nonce. A leaked enrolment token
  alone can't compromise an existing device — it can only start a *new*,
  unconfirmed enrolment, which still needs a live code from that new secret
  to go anywhere.
- **Replay protection**: each `TOTPDevice` tracks `last_used_counter`. A
  code is rejected if its time-step counter is `<=` the last one accepted —
  even a code that's still inside its nominal ±30s validity window can never
  be reused. **This check-and-update is done under `select_for_update()`**
  so two concurrent requests presenting the same code can't both win the
  race (see `accounts/services/totp.py::verify_totp`) — without the lock,
  the second request would read the counter before the first's write
  landed, defeating replay protection under concurrency.
- **Backup codes** are single-use for the same reason and with the same
  locking: `consume_backup_code` re-fetches the device row under
  `select_for_update()` before checking membership and removing the code,
  so two concurrent logins can't both spend the same backup code.
- **Backup codes are hashed with raw SHA-256 + `hmac.compare_digest`**, not
  `make_password`/Argon2. This is intentional, not an oversight: these are
  10-character machine-generated codes from a 32-symbol alphabet (~50 bits
  of entropy) — not human-chosen low-entropy secrets — so slow hashing buys
  no offline brute-force resistance and only adds ~100MiB/verification of
  Argon2 memory cost on an endpoint reachable pre-authentication. See
  `whatsapp/utils.py`'s webhook-signature check for the same pattern applied
  to another high-entropy secret.
- **Lockout is shared** between TOTP-code and backup-code attempts (a Redis
  counter keyed per-user), so an attacker can't get 5 guesses at each
  independently. It reuses the org's existing `max_login_attempts` /
  `lock_duration_minutes` from `security_policy` — no new admin-facing
  knobs. Fails **closed** on a Redis error (503 beats an unmetered
  brute-force window on a pre-auth endpoint).
- **Superusers are not exempt.** The sole System Admin is the account most
  worth protecting, not a special case.
- **Secrets at rest are Fernet-encrypted** (`nexocrm/crypto.py`, fails
  closed if `FERNET_ENCRYPTION_KEY` is unset — see the deploy note below).

### Extending this

- **Adding a new verification method** (e.g. WebAuthn/passkeys): add a
  branch inside `_verify_second_factor` in `accounts/views/two_factor.py`
  alongside the existing TOTP/backup-code checks; the challenge-token
  plumbing and lockout counter are already method-agnostic.
- **Admin-assisted recovery** (currently missing — see Known Gaps below): a
  natural addition would be a `management`-app endpoint, gated by an
  existing admin permission, that deletes a target user's `TOTPDevice` after
  some out-of-band verification step. Do **not** let this bypass audit
  logging — reuse `accounts/services/two_factor.py::audit_2fa_event`.
- **Changing TOTP parameters** (digits, algorithm, interval): don't. Google
  Authenticator ignores the `algorithm`/`digits` query params in the
  `otpauth://` URI and always assumes SHA-1/6-digit/30s — deviating from
  pyotp's defaults produces codes that will never match what the app shows.

### Deploy checklist

- `FERNET_ENCRYPTION_KEY` **must** be set in the environment before any user
  enrolls. Missing key → every 2FA login fails (fails closed, by design —
  not a bug to "fix" by falling back to a default key).
- **Key rotation invalidates every stored secret.** There's no
  re-encryption path; rotating the key means every enrolled user has to
  re-enroll from scratch. Plan rotations accordingly.
- Keep `require_2fa` **off** for any organization with mobile (Flutter)
  users until the mobile client is updated to handle the
  `two_factor_required`/`two_factor_setup_required` response shapes — it's
  out-of-repo and doesn't know about them yet. The default is `false`, so
  nothing changes unless an admin explicitly opts in via
  `PATCH /settings/security/policy/`.

---

## 4. Known gaps

- **No admin-assisted recovery.** If a sole System Admin loses both their
  phone and their backup codes, there is currently no in-product way to
  reset their 2FA. Flag this explicitly before enabling `require_2fa` on any
  single-admin organization.
- **Mobile (Flutter) support is not built.** The response shapes are
  additive (an outdated client just won't see an `access_token` key rather
  than misbehaving), but a mobile user with `require_2fa` on will be stuck
  until the app is updated.
- **Clock drift** beyond the ±30s window produces a generic "invalid code"
  with no diagnostic hint — worth surfacing better UI copy for this
  eventually (e.g. "check your phone's clock").
