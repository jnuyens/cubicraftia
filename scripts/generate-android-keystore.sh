#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# generate-android-keystore.sh — One-time Android release keystore generator
#
# Generates a release.keystore (RSA 2048, 25000-day validity) for signing the
# Cubicraftia Android APK. The keystore must NEVER be committed to the repository
# (it is listed in .gitignore). Its Base64-encoded form is pasted into the GitHub
# Secret SECRET_RELEASE_KEYSTORE_BASE64.
#
# Threat: T-03-01 — keystore leak via committed file.
# Mitigations in this script:
#   - Refuses to run if release.keystore already exists (idempotent / no clobber).
#   - Reminds operator to verify .gitignore exclusion.
#   - Outputs the base64 blob with paste-into-Secrets instructions.
#   - NEVER writes plaintext passwords to disk or to the repo.
#
# Security note (T-03-05): The base64 blob is printed to stdout. Clear your
# terminal scrollback after copying it to GitHub Secrets. See docs/CI_KEYSTORE_SETUP.md.
#
# Usage:
#   bash scripts/generate-android-keystore.sh          # generate keystore
#   bash scripts/generate-android-keystore.sh --check  # check prerequisites only
#
# See docs/CI_KEYSTORE_SETUP.md for the full keystore setup and rotation runbook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

echo ""
echo "=== Cubicraftia Android Release Keystore Generator ==="
echo ""

FAIL=0

# ── Prerequisite checks ────────────────────────────────────────────────────────

# 1. keytool must be on PATH (ships with JDK 11+)
if ! command -v keytool &>/dev/null; then
  echo "ERROR: keytool not found on PATH." >&2
  echo "       Install JDK 17+: brew install openjdk@17" >&2
  echo "       Then add it to PATH: export PATH=\"\$(brew --prefix openjdk@17)/bin:\$PATH\"" >&2
  FAIL=1
else
  KEYTOOL_VER="$(keytool 2>&1 | head -1 || echo 'unknown')"
  echo "[OK]  keytool found."
fi

# 2. base64 must be on PATH (standard on macOS and Linux)
if ! command -v base64 &>/dev/null; then
  echo "ERROR: base64 not found on PATH." >&2
  FAIL=1
else
  echo "[OK]  base64 found."
fi

# 3. .gitignore must exclude release.keystore (safety assertion)
if ! grep -qF "release.keystore" .gitignore 2>/dev/null; then
  echo "ERROR: .gitignore does not exclude 'release.keystore'." >&2
  echo "       Add the following to .gitignore before proceeding:" >&2
  echo "         release.keystore" >&2
  echo "         release.keystore.b64" >&2
  FAIL=1
else
  echo "[OK]  .gitignore excludes release.keystore."
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo ""
  echo "Prerequisites not met. Fix the above issues and re-run." >&2
  exit 1
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo ""
  echo "=== --check mode: all prerequisites satisfied. No keystore generated. ==="
  echo ""
  echo "Run without --check to generate the keystore."
  exit 0
fi

# ── Safety: refuse to clobber an existing keystore ────────────────────────────

if [[ -f "release.keystore" ]]; then
  echo "ERROR: release.keystore already exists in the repository root." >&2
  echo "       This script will NOT overwrite an existing keystore." >&2
  echo "       If you need to regenerate, delete release.keystore manually first." >&2
  echo "       See docs/CI_KEYSTORE_SETUP.md for the rotation procedure." >&2
  exit 1
fi

# ── Generate the keystore ─────────────────────────────────────────────────────

echo "Generating release.keystore (RSA 2048, 25000-day validity)..."
echo ""
echo "You will be prompted to enter a keystore password."
echo "Use a strong password and store it in your password manager."
echo "You will need to add it to GitHub Secrets as SECRET_RELEASE_KEYSTORE_PASSWORD."
echo ""

keytool \
  -genkey \
  -keystore release.keystore \
  -alias release \
  -keyalg RSA \
  -keysize 2048 \
  -validity 25000 \
  -dname "CN=Cubicraftia release, O=Cubicraftia contributors, C=BE"

echo ""
echo "[OK]  release.keystore generated successfully."
echo ""

# ── Base64-encode the keystore ────────────────────────────────────────────────

echo "Encoding keystore to Base64..."
base64 -i release.keystore -o release.keystore.b64

echo "[OK]  release.keystore.b64 written."
echo ""

# ── Print the blob with instructions ─────────────────────────────────────────

echo "=================================================================="
echo "  GitHub Secret: SECRET_RELEASE_KEYSTORE_BASE64"
echo "=================================================================="
echo ""
echo "Copy the text below (the entire Base64 blob) and paste it into:"
echo "  GitHub repo → Settings → Secrets and variables → Actions"
echo "  → New repository secret → Name: SECRET_RELEASE_KEYSTORE_BASE64"
echo ""
echo "--- BEGIN BASE64 KEYSTORE ---"
cat release.keystore.b64
echo "--- END BASE64 KEYSTORE ---"
echo ""

# ── Print fingerprint for verification ────────────────────────────────────────

echo "=================================================================="
echo "  Keystore fingerprint (save for verification)"
echo "=================================================================="
keytool -list -keystore release.keystore -alias release -storepass "$(read -rs -p 'Re-enter keystore password for fingerprint: ' pass; echo "$pass")" 2>/dev/null \
  | grep -A2 "Certificate fingerprint" || true
echo ""

# ── Reminder: .gitignore safety assertion ────────────────────────────────────

echo "=================================================================="
echo "  IMPORTANT: Do NOT commit these files"
echo "=================================================================="
echo ""
echo "Verifying .gitignore exclusions..."

GIT_STATUS="$(git status --short release.keystore release.keystore.b64 2>/dev/null || echo '')"
if echo "$GIT_STATUS" | grep -qE "^(\?\?|A|M) release\.keystore"; then
  echo "WARNING: release.keystore appears to be tracked or staged by git!" >&2
  echo "         Run: git rm --cached release.keystore (if accidentally staged)" >&2
  echo "         Ensure .gitignore contains: release.keystore" >&2
else
  echo "[OK]  release.keystore is excluded by .gitignore (not tracked by git)."
fi

if echo "$GIT_STATUS" | grep -qE "^(\?\?|A|M) release\.keystore\.b64"; then
  echo "WARNING: release.keystore.b64 appears to be tracked or staged by git!" >&2
  echo "         Ensure .gitignore contains: release.keystore.b64" >&2
else
  echo "[OK]  release.keystore.b64 is excluded by .gitignore (not tracked by git)."
fi

echo ""
echo "=================================================================="
echo "  Next steps"
echo "=================================================================="
echo ""
echo "1. Paste the Base64 blob above into GitHub Secret SECRET_RELEASE_KEYSTORE_BASE64"
echo "2. Add your keystore PASSWORD to: SECRET_RELEASE_KEYSTORE_PASSWORD"
echo "3. Add the alias 'release' to:    SECRET_RELEASE_KEYSTORE_USER"
echo "4. Clear your terminal scrollback to remove the Base64 from session memory (T-03-05)"
echo "5. Delete release.keystore and release.keystore.b64 from your local disk when done"
echo "   (or store them in an offline encrypted vault — NOT in the repo)"
echo ""
echo "See docs/CI_KEYSTORE_SETUP.md for the full setup and rotation procedure."
