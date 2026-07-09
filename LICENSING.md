<!--
SPDX-FileCopyrightText: 2026 Cubicraftia contributors
SPDX-License-Identifier: GPL-3.0-or-later AND LicenseRef-AppStore-Exception
-->

# Licensing

**Effective license: GPL-3.0-or-later WITH the App Store Distribution Exception**

This page explains what that means, why it exists, and exactly what it does and does
not change about Cubicraftia's licensing.

## The short version

Cubicraftia's source code is licensed under the **GNU General Public License v3.0 or
later** (`GPL-3.0-or-later`), full text in [LICENSE](LICENSE). On top of that, the
project grants one additional permission under GPLv3 section 7: the
**App Store Distribution Exception**, full text in
[LICENSES/LicenseRef-AppStore-Exception.txt](LICENSES/LicenseRef-AppStore-Exception.txt).

Everywhere except an app-store binary, Cubicraftia is plain GPL-3.0-or-later. The
exception exists solely so an official signed Cubicraftia binary can also be
distributed through the Apple App Store.

## Why the exception exists

Apple's App Store Terms of Service require that apps distributed through the store
can only be installed via Apple's own signed distribution mechanism, tied to an
Apple ID and device, and cannot be freely redistributed copy-to-copy. GPLv3 requires
the opposite: everyone who receives a copy must get the same rights to run, copy,
modify, and redistribute it, and GPLv3 explicitly forbids imposing further
restrictions on those rights (section 7) and specifically targets locked-down
devices that refuse to run user-modified code (section 6, the anti-tivoization
clause). These two sets of terms conflict directly, which is the same conflict that
got VLC and GNU Go pulled from the App Store in the past.

The community-tested fix, used by projects such as wger and Feeel, is a narrow
additional permission under GPLv3 section 7 that reconciles the App Store channel
specifically, while leaving every other channel on plain GPL-3.0-or-later.

## What the exception does

- Permits conveying an official Cubicraftia binary through the Apple App Store, or
  any other application-distribution platform whose own terms would otherwise
  conflict with GPL-3.0-or-later, notwithstanding those terms.
- Applies only to the extent the distribution platform's terms actually require it.

## What the exception does NOT do

- It does not waive, diminish, or restrict any other GPL-3.0-or-later right: you
  can always request the Corresponding Source, run and study and modify the
  software, and redistribute your own modified versions through any channel that
  does not impose those incompatible terms, for example GitHub or a direct
  download from cubicraftia.com.
- It does not apply to Google Play: Google's Play Store terms have no equivalent
  conflict with the GPL (real GPL-licensed games, such as Shattered Pixel Dungeon
  and SuperTuxKart, already ship there without any exception), so Android
  distribution stays plain GPL-3.0-or-later.
- It does not stop a recipient from removing the additional permission from their
  own copy: this is the standard GPLv3 section 7 removability language, see the
  full clause text for the exact wording.

## Status

This clause is drafted and landed now, while the project's copyright is still
held by a single author, which keeps the change simple to make. It is not yet
blessed by the project's retained attorney: that review is tracked separately and
is the remaining step before this exception is considered final. Until sign-off is
recorded, Apple/iOS distribution work (signing, notarization, App Store submission)
stays blocked on this review.

## Full texts

- [LICENSE](LICENSE): GPL-3.0-or-later, unmodified.
- [LICENSES/LicenseRef-AppStore-Exception.txt](LICENSES/LicenseRef-AppStore-Exception.txt):
  the additional permission itself.
- [CONTRIBUTING.md](CONTRIBUTING.md): how this applies to new contributions.
