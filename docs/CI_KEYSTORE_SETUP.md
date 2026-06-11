<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Android Release Keystore Setup

This document describes how to generate the Android release keystore for signing the Cubicraftia APK, how to store it securely in GitHub Secrets, and how to rotate it if it is ever compromised.

> **Security note (T-03-05):** The generation procedure prints the Base64-encoded keystore to stdout. Clear your terminal scrollback after copying it to GitHub Secrets.

---

## Prerequisites

| Tool | Install | Verify |
|------|---------|--------|
| Java JDK 17+ | `brew install openjdk@17` | `keytool -help` |
| `base64` | (standard on macOS and Linux) | `which base64` |
| Git repo with `.gitignore` excluding `release.keystore*` | (Plan 01 adds this) | `grep release.keystore .gitignore` |

---

## Step 1: Generate the keystore

Run the helper script from the repository root:

```bash
bash scripts/generate-android-keystore.sh
```

The script will:
1. Check that `keytool`, `base64`, and `.gitignore` exclusions are present.
2. Refuse to run if `release.keystore` already exists (idempotent / no clobber).
3. Prompt you for a keystore password — **choose a strong password and save it in your password manager immediately**. You will never be able to change this password without regenerating the keystore.
4. Generate `release.keystore` with:
   - Algorithm: RSA 2048
   - Validity: 25,000 days (≈ 68 years — standard for Android release keys)
   - Alias: `release`
   - Distinguished Name: `CN=Cubicraftia release, O=Cubicraftia contributors, C=BE`
5. Base64-encode the keystore to `release.keystore.b64`.
6. Print the Base64 blob to stdout with paste instructions.

---

## Step 2: Add the keystore to GitHub Secrets

1. Copy the entire Base64 blob (between `--- BEGIN BASE64 KEYSTORE ---` and `--- END BASE64 KEYSTORE ---`).
2. Go to your GitHub repository: **Settings → Secrets and variables → Actions → Repository secrets**.
3. Create the following secrets:

| Secret name | Value |
|-------------|-------|
| `SECRET_RELEASE_KEYSTORE_BASE64` | The full Base64 blob from step 1 |
| `SECRET_RELEASE_KEYSTORE_PASSWORD` | The keystore password you chose |
| `SECRET_RELEASE_KEYSTORE_USER` | `release` (the alias you used) |

4. Verify by running a CI workflow that includes the Android export target — the run log should show "Keystore decoded successfully."

---

## Step 3: Confirm .gitignore exclusions

Verify that neither file will be accidentally committed:

```bash
git status release.keystore release.keystore.b64
# Expected: nothing (both files are gitignored)
```

If either file shows as untracked or staged, remove it immediately:

```bash
git rm --cached release.keystore release.keystore.b64 2>/dev/null || true
```

The `.gitignore` (added in Plan 01) should contain:
```
release.keystore
release.keystore.b64
```

---

## Step 4: Clean up local files

Once the secrets are in GitHub, you can (and should) delete the local keystore files:

```bash
rm -f release.keystore release.keystore.b64
```

Or store them in an **offline encrypted vault** (e.g., a password manager's secure notes, a VeraCrypt volume, a hardware security key).

**Do NOT store the keystore in the repository, even in a private branch.**

---

## Step 5: Verify CI succeeds

Push a commit and confirm the Android export job passes in `.github/workflows/ci.yml`. Check the "Restore Android release keystore" step — it should log "Keystore decoded successfully."

---

## Rotation procedure

If the keystore is ever compromised (exposed in a commit, leaked via scrollback, etc.):

1. **Immediately revoke the compromised secret** in GitHub: Settings → Secrets → delete `SECRET_RELEASE_KEYSTORE_BASE64`, `SECRET_RELEASE_KEYSTORE_PASSWORD`, `SECRET_RELEASE_KEYSTORE_USER`.
2. **Generate a new keystore** using `bash scripts/generate-android-keystore.sh` (after removing the old `release.keystore` if it exists).
3. **Update the GitHub Secrets** with the new Base64 blob and new password.
4. **Re-sign any existing releases** that used the old key (or publish new builds with the new key and communicate the change to users).

> **Important:** Android Play Store treats a keystore change as a new app. If the app has already been published with the old key and you rotate to a new key without using Google Play App Signing, existing installations will not be updatable via the new builds. Contact Google Play support for guidance. This is why protecting the keystore from the start matters.

---

## Using Google Play App Signing (recommended for Play Store)

For Play Store publishing, Google recommends enrolling in **Google Play App Signing**, which:
- Stores your upload key separately from the app signing key.
- If your upload key is compromised, Google can generate a new one.
- The app signing key is stored on Google's servers and used to sign the final APK delivered to users.

To enroll: Google Play Console → App → Setup → App integrity → App signing. This is a Phase 5 task.

---

## Secret reference in CI

The Android export step in `.github/workflows/ci.yml` reads:

```yaml
- name: Restore Android release keystore
  if: matrix.target.platform == 'Android'
  env:
    KEYSTORE_B64: ${{ secrets.SECRET_RELEASE_KEYSTORE_BASE64 }}
  run: |
    if [ -n "$KEYSTORE_B64" ]; then
      echo "$KEYSTORE_B64" | base64 -d > release.keystore
      echo "Keystore decoded successfully."
    else
      echo "WARNING: SECRET_RELEASE_KEYSTORE_BASE64 is not set — Android export will be unsigned."
    fi
```

If the secret is not set, the Android build proceeds unsigned (useful for forks that don't have the secret). The resulting APK can still be installed via `adb install` for development but will not be accepted by the Play Store.
