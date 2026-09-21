# Security Audit — Clozr Mobile App

**Date:** 21 September 2026
**Scope:** Whole codebase, plus the actual release artifacts (`app-release.aab`, release manifest, compiled `libapp.so`)
**Version audited:** 1.0.0+7 · `com.nexotech.clozrapp`
**Nature:** Read-only review. **No code was changed.**

---

## The short version

The app is in **better shape than most apps at this stage**. Authentication, token storage, session handling and crash reporting are genuinely well built — several things that usually go wrong here were deliberately done right, with comments explaining why.

There are **two things that should be fixed before this goes to production**, and a handful of smaller items worth doing soon.

| # | Issue | Severity | Fix effort |
|---|---|---|---|
| 1 | Release build points at the **dev backend** | 🔴 High | 1 line |
| 2 | Attachment download can **write outside its folder** | 🔴 High | 3 lines |
| 3 | Customer data cached **unencrypted** and backed up to Google Drive | 🟠 Medium | 1 line + follow-up |
| 4 | Attachment links can open **any app**, not just a browser | 🟠 Medium | 2 lines |
| 5 | App code is **not obfuscated** | 🟠 Medium | build flag |
| 6–13 | Smaller hardening items | 🟡 Low | varies |

---

## 🔴 1. The release build talks to the development server

**What's wrong.** The app's server address has a built-in default of `https://dev.clozr.tech`. If anyone builds a release without explicitly passing the production address, the app silently ships pointing at the development server.

This is not hypothetical. I checked the actual release bundle sitting in `build/` and found `https://dev.clozr.tech` compiled into it.

**Why it matters.** Every real customer's data — logins, contacts, quotes, payment records — would flow into the development environment. Dev environments usually have weaker access control, test data mixed in, and different backup rules. This is a data leak caused purely by a missing build flag.

**Where:** `lib/core/config/api_config.dart:21-24`

**Why it keeps happening:** there is no CI pipeline, no build script, and no Makefile in the repo. The correct flag depends on a person remembering to type it every single time. The README documents the Sentry flags but never mentions `API_BASE_URL`.

**How to fix:**
- Remove the `defaultValue` so the address is empty by default (the app already treats empty as "use mock data").
- Make the app refuse to start in a release build if no address was supplied.
- Commit a one-line release script so the flag can't be forgotten.
- **Delete the existing AAB in `build/`** so nobody uploads it by accident.

---

## 🔴 2. Downloading a chat attachment can write outside its intended folder

**What's wrong.** When you tap an attachment in a WhatsApp conversation, the app saves it using a name the **server** supplies:

```dart
final file = File('${dir.path}/wa_$mediaId${_extensionForMime(contentType)}');
await file.writeAsBytes(bytes);
```

`mediaId` comes straight from the server's JSON with no checking at all — I searched the entire path from the network response to the file write and found no validation anywhere.

**Why it matters.** A file name containing `../` escapes the intended folder. Because the app is writing inside its own private storage, it can reach its own cached customer data and its stored-credentials file. A malicious or compromised backend could turn one tap on an attachment into overwriting those files with content it chooses.

**Honest caveat on likelihood:** this requires the backend itself to be hostile or compromised — it is not something an outsider on the network can trigger, because traffic is encrypted. It's a "don't trust the server blindly" defence, and for a multi-tenant CRM that defence is worth having.

**Where:** `lib/features/messages/presentation/screens/chat_screen.dart:220-222`
Source of the unchecked value: `lib/features/messages/infrastructure/data_sources/remote/messages_remote_ds.dart:139,159`

**How to fix:** don't build a filename out of server data. Either hash it, or reject anything that isn't plain letters/numbers before using it, then confirm the final path is still inside the intended folder.

---

## 🟠 3. Customer data is cached unencrypted, and Android backs it up to the cloud

**What's wrong.** Two things that individually are minor but combine badly:

1. The app caches raw server responses on disk **without encryption** — leads, customers, quotes, payments, notes, WhatsApp message text, and the signed-in user's profile.
2. The Android manifest never sets `allowBackup="false"`, so Android's default (**on**) applies.

I confirmed both against the final release manifest, not just the source.

**Why it matters.** The cached customer records get swept into Google's automatic backup — meaning a copy of your tenant's CRM data lands in **that employee's personal Google Drive**, outside the customer's control. For a B2B product with data-processing obligations, that's a compliance problem, not just a theft scenario. It also means a lost or stolen phone, or a forensic extraction, yields readable customer data.

**Good news:** login tokens are **not** affected. They're stored properly in the Android Keystore / iOS Keychain, and the encryption key never leaves the device, so a restored backup can't decrypt them.

**Where:** `android/app/src/main/AndroidManifest.xml:15-19`, `lib/core/storage/app_cache.dart:42`

**How to fix:** add `android:allowBackup="false"` (one line, do this before release). Then, as a follow-up, encrypt the cache using a key kept in secure storage.

---

## 🟠 4. Attachment links can launch any app on the phone

**What's wrong.** When opening an attachment, the app accepts **whatever address the server sends** and hands it to the operating system, with no check that it's actually a web link.

**Why it matters.** A hostile backend could make a file attachment open the phone dialler on a premium-rate number, or trigger a deep link into another installed app — all disguised as "open this document". This affects all eight places attachments can be opened.

**What is *not* a risk here** (I checked rather than assumed): this cannot run JavaScript and cannot construct arbitrary Android intents. The plugin doesn't support those paths. So it's app-launching, not code execution.

**Where:** `lib/core/utils/attachment_link.dart:27`

**How to fix:** only allow `https` links. One check in one function covers all eight screens.

---

## 🟠 5. The app's code is not obfuscated

**What's wrong.** A plain `flutter build` does **not** obfuscate Dart code — it has to be asked for explicitly, and nothing in this project does.

I confirmed it against the shipped binary: names like `TokenStorage`, `AuthInterceptor`, `ApiService`, `LeadsRemoteDataSource` and even original source file paths are readable strings inside the release bundle.

**Why it matters.** Anyone who downloads the app from the Play Store gets a clearly labelled map of how your authentication, token storage and caching work. It doesn't break anything by itself, but it turns reverse-engineering your API from a slog into an afternoon.

**How to fix:** build with `--obfuscate --split-debug-info=build/symbols/<version>`, and keep the symbol folder for each release so crash reports stay readable.

> Note: Android/Java code **is** already shrunk and obfuscated — Flutter turns R8 on automatically. This gap is only on the Dart side.

---

## 🟡 Smaller items (Low severity)

**6. Debug builds print login tokens to the device log.**
The HTTP logger prints full response bodies, which includes the `/auth/login/` response — i.e. the tokens themselves. This is **debug-only** and genuinely cannot reach production (verified both in the code and by confirming the logger is absent from the release binary). The risk is a developer pasting a log into a ticket. The code comment already marks it `TEMPORARY`. → `lib/core/network/api_service.dart:50`

**7. Crash reports can include what users typed into search boxes.**
Sentry is configured tightly — no request bodies, no headers, no screenshots, tokens stripped — but the request **URL and query string** are kept, and browsing history breadcrumbs aren't filtered. Since searches send terms in the URL, a customer name or email typed into a search box can reach Sentry on a crash. → `lib/core/monitoring/sentry_config.dart:113`

**8. Downloaded chat files are never deleted, and survive logout.**
Customer documents fetched from WhatsApp threads stay in the app's temp folder indefinitely. Logout clears the database and tokens but not these files, so on a shared device the next person inherits them. → `chat_screen.dart:219-222`

**9. The "is the connection secure?" check doesn't run in release.**
There's a check that the server address uses HTTPS, but it's written as an `assert`, which Dart removes from release builds. A release built with an `http://` address would send data in the clear without complaint. Low because it needs someone to deliberately pass a bad address at build time. → `lib/app/bootstrap/app_bootstrap.dart:49-53`

**10. iOS stored tokens can move to another device.**
Keychain items don't specify "this device only", so the refresh token is carried in an encrypted iTunes/Finder backup and can be restored onto a different phone. → `lib/core/storage/token_storage.dart:10-12`

**11. No screenshot protection or re-authentication.**
Customer records can be screenshotted, appear in the app-switcher preview, and reopening the app goes straight in with no PIN or biometric prompt. Whether this matters is a product decision.

**12. A failed session restore leaves data on disk.**
If restoring a session fails, the user is sent to the login screen but the refresh token and cached customer data are left in place. A later forced logout then does nothing, due to a guard clause. Data isn't visible through the app — a new sign-in clears it first — but it lingers on disk. → `lib/features/auth/application/providers/auth_providers.dart:112-116, 244`

**13. The signing keystore lives inside the project folder.**
`android/clozr-upload.jks` and `android/key.properties` are correctly ignored by git, correctly permissioned, and have **never** been committed. But they sit in a folder people zip up, sync to cloud drives, or copy into build containers — none of which respect `.gitignore`. Also, the root `.gitignore` has no keystore patterns; protection comes only from `android/.gitignore`. → Move the keystore outside the repo and point `key.properties` at the absolute path.

**14. Not security, but worth doing:** `ITSAppUsesNonExemptEncryption` is missing from the iOS `Info.plist`, so every App Store upload stops to ask the export-compliance question. Adding `<false/>` is correct here and removes the friction.

**15. No certificate pinning.** Standard for most apps, but it means anyone who can install a trusted certificate on the device (corporate device management, or a user installing a proxy) can read CRM traffic. Worth a deliberate decision rather than an accident.

---

## ✅ What's already done right

This deserves saying, because a lot of it is stuff that commonly goes wrong:

**Secrets**
- **Nothing sensitive has ever been committed** — checked all 105 commits. No keystore, no passwords, no API keys, no private keys. The only match was a blank template file.
- The hardcoded Sentry DSN is **not** a leak — it's a write-only identifier that ships in every Sentry app by design.

**Login & tokens**
- Tokens are in the platform keychain/keystore, **never** in the general database — and Android's `encryptedSharedPreferences` was deliberately switched on (it's off by default).
- The token-refresh flow can't loop infinitely, retries exactly once, and uses a separate network client so a failed refresh can't recurse.
- A revoked session is detected and logs the user out instead of trying to refresh a dead token.
- **No login token is ever sent to a third-party server.** I traced every network path, including image loading and attachment links — nothing leaks the token off your API origin.
- Logout is thorough and correctly ordered: it clears cached data *before* dropping the token, blacklists the token server-side, and resets the crash-reporting identity.
- No hardcoded passwords, demo accounts or API keys anywhere.
- "Remember me" stores only the email address, in the keychain — never a password. There's a test asserting this.

**Network**
- Plain HTTP is switched off on both platforms.
- **No "accept any certificate" bypass** — I looked for this specifically; the classic dangerous shortcut is absent.

**Crash reporting**
- Personally identifiable information is switched off, screenshots off, view hierarchy off.
- A custom scrubber removes authorization and cookie headers, and drops request bodies entirely.
- Only an anonymous user ID is sent — no name, no email.

**Android**
- The app requests only **two** permissions: internet and network state. No storage, camera, location or contacts — not even indirectly through a dependency.
- All content providers are correctly locked to the app.
- Java/Kotlin code is shrunk and obfuscated.
- Debug logging is properly compiled out of release builds.

**Attack surface**
- **No deep links at all** — the app cannot be launched or driven by a crafted web link. (Worth stating clearly: the `https` entry in the manifest is an outbound visibility declaration, not an entry point. It's easy to misread as a vulnerability.)
- No WebView and no HTML rendering anywhere, which removes a whole category of web-style vulnerabilities.
- Phone-number dialling is built safely using proper URI encoding, and numbers are stripped to digits.
- Picked files never have their names used to build a file path.
- Downloads go to private app storage, never shared storage.
- **All 122 dependencies come from pub.dev** — no git or local dependencies, so no supply-chain side doors.

---

## Recommended order

**Before you ship:**
1. Pin down the production server address and delete the dev-pointed AAB (#1)
2. Validate the attachment filename (#2)
3. Add `android:allowBackup="false"` (#3)
4. Allowlist `https` for attachment links (#4)
5. Turn off `responseBody` logging (#6)

**Soon after:**
6. Add `--obfuscate` to the release build (#5)
7. Encrypt the local cache (#3 follow-up)
8. Strip query strings from crash reports (#7)
9. Clean up temp files on logout (#8, #12)
10. Move the keystore out of the repo (#13)

**A note on root causes:** items #1 and #5 both exist because every release flag depends on someone typing it correctly from memory. A single committed release script — or a CI job — would prevent both, and is probably the highest-value thing on this list.

---

## How this was checked

Four parallel reviews covering secrets and build configuration, authentication and session handling, logging and telemetry, and untrusted-input handling. Findings were cross-checked against each other and the significant ones verified independently against the **actual compiled release artifacts**, not just source code.

Three hypotheses were investigated and **ruled out** rather than reported: login tokens leaking to the CDN, tokens stored in the unencrypted database, and the HTTP logger running in production. All three turned out to be handled correctly.
