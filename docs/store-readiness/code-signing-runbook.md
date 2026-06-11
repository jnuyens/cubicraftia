<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Code Signing Runbook

**Product:** Cubicraftia v1.0
**Prepared:** 2026-05-29
**Covers:** macOS (notarisation), iOS (TestFlight), Android (Play Store), Windows (optional)

This runbook documents the signing configuration for all five export targets. Signing credentials are **never committed to the repository** — they live in operator secrets (GitHub Actions) or a local keychain.

---

## Table of Contents

1. macOS — Apple Developer ID + Notarisation
2. iOS — Apple Developer Program + TestFlight
3. Android — Google Play App Signing
4. Windows — Authenticode (Optional)
5. GitHub Actions Secrets Reference
6. Sign-In with Apple (SIWA) Decision
7. Annual Renewal Reminders

---

## 1. macOS — Apple Developer ID + Notarisation

### Prerequisites

- **Apple Developer Program membership** ($99/yr) — required. The Developer ID certificate requires a paid membership.
- **Xcode** installed on the signing machine (or macOS runner in CI).
- An **Apple ID** with access to the developer account.

### Step 1 — Create a Developer ID Application certificate

1. Open Xcode → Settings → Accounts → Manage Certificates.
2. Click "+" → "Developer ID Application".
3. Export the certificate as a `.p12` file with a password. Keep this file secure.
4. Base64-encode the `.p12` for GitHub Actions:
   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```
5. Store as GitHub Actions secret `MACOS_CERTIFICATE_P12`.
6. Store the certificate password as `MACOS_CERTIFICATE_PASSWORD`.

### Step 2 — Sign the exported `.app`

After Godot exports `Cubicraftia.app`:

```bash
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  Cubicraftia.app
```

The `--options runtime` flag is required for notarisation.

### Step 3 — Create a `.zip` for notarisation

```bash
ditto -c -k --keepParent Cubicraftia.app Cubicraftia.zip
```

### Step 4 — Submit for notarisation

```bash
xcrun notarytool submit Cubicraftia.zip \
  --apple-id "your@apple.id" \
  --password "@keychain:AC_PASSWORD" \
  --team-id "YOUR_TEAM_ID" \
  --wait
```

Or using an App Store Connect API key (recommended for CI):

```bash
xcrun notarytool submit Cubicraftia.zip \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id "KEY_ID" \
  --issuer "ISSUER_UUID" \
  --wait
```

### Step 5 — Staple the notarisation ticket

```bash
xcrun stapler staple Cubicraftia.app
```

### Step 6 — Verify

```bash
spctl --assess --verbose Cubicraftia.app
# Expected output: Cubicraftia.app: accepted
```

### CI integration

The macOS export job in `.github/workflows/ci.yml` uses `macos-latest` runner. Add notarisation as a post-export step in that job. Required secrets: `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_PRIVATE_KEY`.

---

## 2. iOS — Apple Developer Program + TestFlight

### Prerequisites

- **Apple Developer Program membership** ($99/yr) — required. Must be purchased before this step.
- A registered **App ID** in App Store Connect for `com.cubicraftia.game`.
- An **iOS Distribution certificate** + **provisioning profile** (App Store distribution).

### Step 1 — Create an iOS Distribution certificate

1. Open Xcode → Settings → Accounts → Manage Certificates.
2. Click "+" → "Apple Distribution".
3. Export as `.p12` with a password.
4. Base64-encode for GitHub Actions:
   ```bash
   base64 -i AppleDistribution.p12 | pbcopy
   ```
5. Store as secret `APPLE_CERTIFICATE_P12`.
6. Store password as `APPLE_CERTIFICATE_PASSWORD`.

### Step 2 — Create a provisioning profile

1. In App Store Connect → Certificates, IDs & Profiles → Profiles → New.
2. Type: App Store Distribution.
3. Select the App ID (`com.cubicraftia.game`).
4. Select the Distribution certificate.
5. Download the `.mobileprovision` file.
6. Base64-encode for GitHub Actions:
   ```bash
   base64 -i Cubicraftia_AppStore.mobileprovision | pbcopy
   ```
7. Store as secret `APPLE_PROVISIONING_PROFILE`.

### Step 3 — App Store Connect API key (for TestFlight upload)

1. App Store Connect → Users and Access → Keys → New API Key.
2. Access: "App Manager" role is sufficient for TestFlight uploads.
3. Download the `.p8` key file — **you can only download it once**.
4. Note the **Key ID** and **Issuer ID**.
5. Store secrets:
   - `APP_STORE_CONNECT_KEY_ID` — the 10-character key ID
   - `APP_STORE_CONNECT_ISSUER_ID` — the UUID issuer ID
   - `APP_STORE_CONNECT_PRIVATE_KEY` — contents of the `.p8` file

### Step 4 — Configure Godot iOS export preset

In `export_presets.cfg` (iOS preset):

```ini
[preset.N]
name="iOS"
platform="iOS"
...
options/application/app_store_team_id="YOUR_TEAM_ID"
options/application/bundle_identifier="com.cubicraftia.game"
options/application/provisioning_profile_uuid_debug=""
options/application/provisioning_profile_uuid_release="<UUID from the .mobileprovision file>"
options/application/code_sign_identity_debug="iPhone Developer"
options/application/code_sign_identity_release="iPhone Distribution"
```

### Step 5 — GitHub Actions CI (automated)

The `export_ios` job in `.github/workflows/ci.yml` handles:
1. Decoding `APPLE_CERTIFICATE_P12` and installing it into the build keychain.
2. Decoding `APPLE_PROVISIONING_PROFILE` and placing it in `~/Library/MobileDevice/Provisioning Profiles/`.
3. Running `godot --headless --export-release "iOS" build/Cubicraftia.ipa`.
4. Uploading the `.ipa` to TestFlight via `dulvui/godot-ios-upload@v4`.

The job is conditional on `APPLE_CERTIFICATE_P12 != ''` — it skips gracefully if the secret is absent.

### Step 6 — Verify the TestFlight build

1. Check App Store Connect → TestFlight → Builds. The build should appear within 15–30 minutes.
2. Add internal testers and confirm the build installs and launches.
3. For external beta review, submit the build for Beta App Review (typically 1–2 days).

---

## 3. Android — Google Play App Signing

### Prerequisites

- **Google Play Console account** ($25 one-time registration fee).
- An Android **upload key** (distinct from the app signing key managed by Google Play).

### Understanding upload key vs. app signing key

Google Play App Signing separates two keys:
- **App signing key** — Google holds this; it signs the APK/AAB that users download. You cannot export this key from Google's infrastructure.
- **Upload key** — You hold this; it signs the AAB you upload. Google verifies your upload key, then re-signs with the app signing key before distribution.

This model protects users even if your upload key is compromised (you can revoke and rotate it).

### Step 1 — Generate an upload key

```bash
keytool -genkey -v \
  -keystore cubicraftia-upload.keystore \
  -alias cubicraftia \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

Store the keystore password and key password securely.

### Step 2 — Encode for GitHub Actions

```bash
base64 -i cubicraftia-upload.keystore | pbcopy
```

Store as secret `SECRET_RELEASE_KEYSTORE_BASE64` (already referenced in ci.yml).

Store passwords as `KEYSTORE_PASSWORD` and `KEY_PASSWORD`.

### Step 3 — Configure Godot Android export preset

In `export_presets.cfg` (Android preset):

```ini
[preset.N]
name="Android"
platform="Android"
...
options/keystore/release="release.keystore"
options/keystore/release_user="cubicraftia"
options/keystore/release_password="<KEYSTORE_PASSWORD>"
```

In CI, the keystore is decoded from `SECRET_RELEASE_KEYSTORE_BASE64` to `release.keystore` before the export step.

### Step 4 — Enrol in Google Play App Signing

During the first upload to the Play Console:
1. Go to Release → Setup → App integrity.
2. Choose "Let Google manage and protect your app signing key" (recommended).
3. Upload a signed AAB — Google will extract the app signing key from this first upload.

After enrolment, only your upload key is needed for future uploads.

### Step 5 — Upload to Play Console

```bash
# Using bundletool (manual)
bundletool build-apks --bundle=Cubicraftia.aab \
  --output=Cubicraftia.apks \
  --ks=cubicraftia-upload.keystore \
  --ks-key-alias=cubicraftia \
  --ks-pass=pass:PASSWORD
```

Or use `fastlane supply` for automated Play Store uploads (post-v1 CI enhancement).

---

## 4. Windows — Authenticode Signing (Optional for v1)

Windows code signing is not required for itch.io distribution. It is optional for the Microsoft Store (not targeted in v1). Without signing, Windows SmartScreen may show an "Unknown publisher" warning on first run — this is acceptable for v1.

### If signing is required (future)

1. Purchase a **code signing certificate** from a trusted CA (e.g., DigiCert, Sectigo). OV (Organisation Validation) certificates are required for EV-level SmartScreen reputation.
2. Sign the `.exe` using `signtool.exe`:
   ```bash
   signtool sign /fd sha256 /a /tr http://timestamp.digicert.com /td sha256 Cubicraftia.exe
   ```
3. For CI, the certificate can be stored as a PFX base64 secret and decoded before the signing step.

---

## 5. GitHub Actions Secrets Reference

| Secret name | Platform | Purpose |
|-------------|----------|---------|
| `APPLE_CERTIFICATE_P12` | iOS | Base64-encoded iOS Distribution certificate (.p12) |
| `APPLE_CERTIFICATE_PASSWORD` | iOS | Password for the .p12 certificate |
| `APPLE_PROVISIONING_PROFILE` | iOS | Base64-encoded App Store .mobileprovision file |
| `APP_STORE_CONNECT_KEY_ID` | iOS, macOS | App Store Connect API key ID (for TestFlight + notarisation) |
| `APP_STORE_CONNECT_ISSUER_ID` | iOS, macOS | App Store Connect API issuer UUID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | iOS, macOS | App Store Connect API .p8 private key content |
| `MACOS_CERTIFICATE_P12` | macOS | Base64-encoded Developer ID Application certificate |
| `MACOS_CERTIFICATE_PASSWORD` | macOS | Password for the macOS .p12 certificate |
| `SECRET_RELEASE_KEYSTORE_BASE64` | Android | Base64-encoded Android upload keystore |
| `KEYSTORE_PASSWORD` | Android | Android keystore password |
| `KEY_PASSWORD` | Android | Android key alias password |

> Add these in the repository under Settings → Secrets and variables → Actions → Repository secrets.
> Never log these values (`echo "$SECRET"` is forbidden; the CI jobs use `-x`-free shell steps).

---

## 6. Sign-In with Apple (SIWA) Decision

**Cubicraftia v1 does NOT require SIWA.**

Apple's App Store guidelines require Sign-in with Apple when an app offers third-party sign-in (Google, Facebook, etc.). Cubicraftia v1 uses **email + password only** — no third-party identity provider is offered. Therefore the SIWA requirement does not apply.

The `sign_in_with_provider()` stub in `src/autoload/friends_client.gd` exists as a forward-compatibility hook but is not wired to any Apple/Google OAuth flow in v1. If a third-party sign-in option is added in a future version, SIWA must be implemented simultaneously.

Reference: Apple App Store Review Guidelines §4.8 Sign-In with Apple.

---

## 7. Annual Renewal Reminders

| Certificate | Valid for | Renewal action |
|-------------|-----------|----------------|
| Apple Developer Program membership | 1 year | Renew at developer.apple.com; certificates auto-renew |
| iOS Distribution certificate | 1 year | Create new in Xcode → update GitHub secret |
| Provisioning profile | 1 year | Regenerate in App Store Connect → update GitHub secret |
| App Store Connect API key | Until revoked | Rotate annually as a security best practice |
| macOS Developer ID certificate | ~3 years | Renew before expiry; re-sign and re-notarise all builds |
| Android upload keystore | 10 000 days (keytool default) | Do not lose the keystore — Google cannot recover it |

Set calendar reminders at 60 days before each expiry.
