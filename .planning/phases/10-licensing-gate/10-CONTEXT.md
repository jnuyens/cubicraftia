# Phase 10: Licensing Gate - Context

**Gathered:** 2026-07-09 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Add a GPLv3 §7 "App Store" supplemental-permission (additional-permission) exception to the project's licensing so an official signed binary can be distributed through Apple's App Store (and functionally-equivalent stores whose terms are incompatible with the GPL), without changing the GPL-3.0-or-later license for everything else. This unblocks the Apple/iOS distribution track (SIGN-05, STORE-02). It does NOT block the Android/desktop/backend tracks. Scope is licensing text + docs only — no signing, no submission, no code.

Requirement: **LICENSE-01**.
</domain>

<decisions>
## Implementation Decisions

### Exception mechanism
- **D-01:** Add an **additional permission under GPLv3 section 7** — an "App Store Distribution Exception" — granting permission to convey the covered work in object-code form through application distribution platforms (Apple App Store and any store whose terms impose restrictions incompatible with GPLv3 §6 anti-tivoization / §7 further-restrictions), notwithstanding those store terms. Base the wording on the community-tested pattern used by wger and Feeel (the widely-referenced GPL-on-App-Store exception).
- **D-06:** Name **Apple App Store** explicitly and generalize to "any application-distribution platform whose terms would otherwise be incompatible with this License." Google Play needs no exception but is harmlessly covered.

### Scope of the grant (what it does and does NOT do)
- **D-03:** The exception permits distribution through such stores **solely to the extent the store's terms require**; it does NOT waive users' rights to receive Corresponding Source, to build and run their own modified versions, or any other GPL right. Everything except the store-distribution channel stays full GPL-3.0-or-later. Include the standard §7 language that a downstream recipient MAY remove the additional permission.

### Placement (REUSE 3.x compliant — do not break `reuse lint`)
- **D-02:** The repo is REUSE-compliant (`.reuse/dep5` blanket GPL-3.0-or-later + `LICENSES/` dir). Land the exception as:
  1. A dedicated license-text file `LICENSES/LicenseRef-AppStore-Exception.txt` (REUSE `LicenseRef-` custom-license convention), and
  2. A human-readable `LICENSING.md` at repo root explaining the effective license = **"GPL-3.0-or-later WITH the App Store Distribution Exception"**, why it exists (Apple ToS vs GPL), and what it does/doesn't grant.
  3. Update README's License section to point at `LICENSING.md` and state the effective license string.
  4. Keep `reuse lint` green (add the LicenseRef file to `LICENSES/`; reference it where appropriate). Do NOT rewrite every file's SPDX header — the additional permission attaches to the work's license grant, documented centrally.

### Contributor preservation (keep the exception landable long-term)
- **D-05:** Add a CONTRIBUTING note (or DCO/inbound=outbound statement) that contributions are licensed **"GPL-3.0-or-later WITH the App Store Distribution Exception."** This is the mechanism the research flagged: the exception is cheap to add now because git history is 100% single-author (jnuyens@linuxbe.com, verified); this note preserves the ability as external contributors arrive so the incompatibility is never silently reintroduced.

### Attorney sign-off (human gate)
- **D-04:** The exact clause wording is **DRAFTED and landed now** (solo-authorship window is time-sensitive), but LICENSE-01 is only *complete* once the retained attorney blesses the wording. Treat attorney sign-off as a **human_needed verification item**, not an engineering blocker — the drafted clause ships immediately and the attorney may refine wording. The plan must clearly mark the attorney review as the outstanding human gate.

### Claude's Discretion
- Exact filename casing for the LicenseRef file (follow REUSE conventions).
- Whether the effective-license explanation lives in `LICENSING.md` alone or is mirrored in a short `NOTICE`.
- Precise prose of the drafted clause, within the wger/Feeel-derived structure.
</decisions>

<specifics>
## Specific Ideas

- The pitfalls research is explicit: this is the same conflict that got VLC and GNU Go pulled from the App Store; the wger/Feeel §7 exception is the established fix. Mirror their structure rather than inventing new wording.
- Do NOT waive anti-tivoization more broadly than the store-distribution channel requires — keep the grant narrow.
- Player-facing / marketing copy must not imply an off-store cheaper purchase path (Apple anti-steering) — but that's a STORE-phase concern, noted only.
</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The blocker + the fix
- `.planning/research/PITFALLS.md` — HARD BLOCKER 1: full GPL-3.0-vs-Apple-App-Store analysis, precedent (VLC, GNU Go), and the GPLv3 §7 exception recommendation with the wger/Feeel pattern.
- `.planning/research/SUMMARY.md` § Watch Out For → HARD BLOCKERS — the urgency (solo-authorship window) and sequencing (phase-0 gate before any iOS work).

### Requirement + license setup
- `.planning/REQUIREMENTS.md` — LICENSE-01 (and the milestone stack-decision notes).
- `.reuse/dep5` — current REUSE blanket declaration (GPL-3.0-or-later for all files).
- `LICENSES/GPL-3.0-or-later.txt` — canonical GPL text the exception amends.
- `README.md` §License — current license statement to update.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- REUSE 3.x tooling already in place (`.reuse/dep5`, `LICENSES/` with GPL-3.0-or-later / MIT / OFL-1.1). The `reuse lint` gate exists — the new LicenseRef file must keep it green.
- CI already runs a glossary/allowlist license-adjacent check (per prior decisions); confirm the new licensing docs pass any doc-content gates.

### Established Patterns
- `reuse-dep5-blanket` decision (STATE.md): blanket SPDX coverage via `.reuse/dep5` rather than per-file headers where practical — the exception follows the same central-declaration approach.

### Integration Points
- README License section; a new root `LICENSING.md`; `LICENSES/LicenseRef-AppStore-Exception.txt`; CONTRIBUTING (create or amend) for the contributor-licensing note.
</code_context>

<deferred>
## Deferred Ideas

- Apple anti-steering / IAP-only wording review — belongs to Phase 16 (Mobile Store Submission), not here.
- COPPA / EULA attorney review is a separate operator/legal gate (v1.0 carryover); the attorney engagement that blesses this clause can bundle it, but it is not LICENSE-01 scope.
</deferred>

---

*Phase: 10-licensing-gate*
*Context gathered: 2026-07-09*
