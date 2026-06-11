# Cubicraftia — Privacy Policy

**Version 1.0 — Effective 2026-05-29**

*Template — attorney review required for GDPR, COPPA, and local data-protection law.*

## Summary

- We collect only what is needed to run the game and keep it safe.
- We do not sell your data, show ads, or share data with third parties.
- Delete your account and all data at any time.
- Under-13 accounts require parental approval before online features unlock.

## 1. What We Collect

**Account data:** email, hashed password (never plain text), username.

**Social data:** friend list, blocked list, world ownership.

**Parental consent data (under-13 only):** parent email (to send the consent link), consent record with timestamp. Deleted with the account.

**Crash data (opt-in, anonymous):** device type, frame rate, crash reports. Not linked to your account.

We do **not** collect: date of birth (only the "under 13" flag), advertising IDs, location, or voice data.

## 2. How We Use Your Data

Authentication and online features (friends, sessions, invites). No advertising or profiling.

## 3. Parental Consent (COPPA)

Under-13 accounts require a parent or guardian email. We send a consent link; the parent confirms and consents. This uses the FTC's email-plus method under COPPA. Until consent arrives, only solo offline play is available. Parents may revoke via the revoke link in the consent email.

## 4. Data Processors

Supabase (self-hosted, Apache-2.0) for auth and storage. No analytics SDKs, ad networks, or tracking.

## 5. Data Retention

Retained while active; deleted within 30 days of account deletion. Moderation reports kept 90 days. CSAM reports forwarded to the National Center for Missing and Exploited Children (NCMEC) per 18 U.S.C. § 2258A and purged within 24 hours.

## 6. Your Rights (GDPR)

- **Access:** Request a data copy by email.
- **Rectification:** Correct data in Settings.
- **Erasure:** Delete account from Settings; data removed within 30 days.
- **Portability:** Data export on request by email; automated download planned for a future update.
- **Objection:** Opt out of crash reporting in Settings.

## 7. Parental Rights

Parents may review or delete data for an under-13 account, or revoke consent, by contacting us (Section 9).

## 8. Security

Passwords hashed with bcrypt. Transit encrypted with TLS. World saves stored locally on your device.

## 9. Contact

*operator-contact-email@example.com — replace before public release.*

## 10. Changes

Material changes prompt in-app review and acceptance before continuing.

## 11. Local Onboarding Telemetry

Cubicraftia records an anonymous local event log at `user://telemetry.cfg` on your device.
This log is used for game improvement analysis during playtesting. It is **never transmitted to
our servers or any third party** in v1. The log contains only:

- A Unix timestamp (integer seconds since epoch)
- An event name from a fixed list (e.g. `title_shown`, `ftue_complete`, `signup_started`)

No personal information, usernames, world names, player positions, device identifiers, or
account identifiers are recorded. The event list is exhaustive and locked:
`title_shown`, `deep_link_received`, `signup_started`, `signup_complete`, `signin_complete`,
`avatar_picker_shown`, `avatar_complete`, `world_select_shown`, `world_created`, `world_loaded`,
`ftue_step_1_complete`, `ftue_step_2_complete`, `ftue_step_3_complete`, `ftue_complete`,
`invite_joined`.

The log is capped at **10,000 entries** using a FIFO rotation (oldest events are dropped when
the cap is exceeded). You can delete this file at any time by clearing the app's local storage
in your device's app settings.
