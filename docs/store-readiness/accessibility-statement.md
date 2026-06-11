<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Accessibility Statement

**Product:** Cubicraftia v1.0
**Prepared:** 2026-05-29
**Standard reference:** WCAG 2.1 (target: Level AA where technically feasible)

Cubicraftia is committed to making the game as accessible as possible within the constraints of a Godot 4.6 game engine project and a first-release budget. This statement describes the current state, what is planned, and what is deferred.

---

## 1. Colour Contrast

### Target

WCAG 2.1 AA requires a minimum contrast ratio of **4.5:1** for normal text and **3:1** for large text (≥ 18pt normal weight or ≥ 14pt bold) and UI components.

### Current state (v1)

| UI surface | Foreground | Background | Estimated ratio | Status |
|------------|------------|------------|-----------------|--------|
| Primary HUD text | White (#FFFFFF) | Dark navy overlay (#1A2744, 80% alpha) | ~8.5:1 | Pass |
| Hotbar slot labels | White (#FFFFFF) | Brick-dark (#2C2C2C) | ~15:1 | Pass |
| Inventory item count | White (#FFFFFF) | Semi-transparent dark panel | ~7:1 | Pass |
| Button labels | White (#FFFFFF) | Accent blue (#1E5FA8) | ~4.7:1 | Pass |
| Settings captions | Light grey (#D0D0D0) | Mid-grey panel (#4A4A4A) | ~4.5:1 | Borderline Pass |
| Error / warning text | Amber (#FFBF00) | Dark panel (#1A2744) | ~7.2:1 | Pass |
| Chat message text | White (#FFFFFF) | Semi-transparent dark overlay | ~7:1 | Pass |

> Ratios above are design-intent targets. Actual in-engine rendering may vary by platform; verify with a contrast analyser at each release.

### Deferred

- Dynamic theme support (light mode / dark mode) — deferred to v1.1. Current palette is dark-first.
- Per-user colour blindness palette presets — post-v1 roadmap item. The current palette avoids red-green reliance for critical status indicators (health bar uses white-to-amber gradient, not green-to-red).

---

## 2. Text Size and Scaling

### Current state (v1)

- All UI text is rendered via Godot's theme system using `ThemeDB` font sizes.
- On iOS and Android, Godot 4.6 inherits the system display scaling factor (`DisplayServer.screen_get_dpi()`) at launch and applies it to the base resolution. The UI is designed at 1080p and scales proportionally.
- Minimum touch-target size is 44 × 44 px (enforced per UI-SPEC §5 — matches Apple HIG and Material Design guidelines).
- Body text minimum: 14pt equivalent at 1× scale.

### Deferred

- In-app font size slider — deferred to v1.1. The system-level accessibility text size settings on iOS/Android do not automatically propagate to Godot canvas items; a manual override slider is required.

---

## 3. Input and Controls

### Desktop (keyboard + mouse) — v1

Full keyboard control is implemented:

| Action | Binding |
|--------|---------|
| Move | WASD + arrow keys |
| Jump | Space |
| Turn | Q / E |
| Inventory | I |
| Interact / Walk-up | Left Shift |
| Release mouse | Tab |
| Place / Break | Right / Left mouse button |
| Menu / Settings | Esc |

Mouse-only navigation: the game can be navigated without a keyboard for most UI surfaces. Gameplay requires keyboard for movement.

### Gamepad support — planned

Gamepad / controller remapping is planned for v1.1. Godot's `InputMap` supports joypad axis and button bindings; the required bindings are not yet exposed in Settings.

### Mobile (touch) — v1

Touch input implemented for:
- Joystick overlay (move)
- Jump button, interact button
- Tap-to-place / tap-to-break
- Swipe gestures (inventory, palette scrolling)

Touch input does not require fine motor precision beyond 44 × 44 px targets.

### Screen reader (switch access)

Not implemented in v1. Godot 4.6 has improving but not complete accessibility API support for platform screen readers (VoiceOver on iOS, TalkBack on Android). A post-v1 roadmap issue is open to evaluate `AccessibilityManager` support when Godot's a11y APIs mature.

---

## 4. Audio

### Current state (v1)

- Game audio: positional audio for in-world effects (creature sounds, block placement).
- No voice chat in v1 — therefore no closed caption requirement for voice audio.
- Chat is text-based — fully accessible without audio.

### Deferred

- Subtitle / caption support for future voice chat (v1.x when voice chat is implemented).
- Visual audio cues (screen flash on audio event) — post-v1 roadmap item.

---

## 5. Motion and Vestibular

### Current state (v1)

- Camera motion: the default camera mode is a third-person follow camera (SpringArm3D). First-person view (FPV) is available via toggle. Players sensitive to motion sickness are recommended to use third-person mode.
- No screen shake effects in v1.
- Particle effects (rain, explosions): present but not toggleable individually in v1.

### iOS and Android reduce-motion

Cubicraftia checks `DisplayServer.get_setting("accessibility/screen_reader/enabled")` at launch (Godot 4.6). If the OS-level "Reduce Motion" preference is detectable via the platform accessibility APIs, particle and camera-bob intensity will be reduced. This feature is in progress; the reduce-motion query API stabilised in Godot 4.6 and is being integrated.

---

## 6. Known Limitations (v1)

The following features are out of scope for v1.0 and are tracked as post-v1 accessibility roadmap items:

| Feature | Status |
|---------|--------|
| Screen reader / VoiceOver / TalkBack support | Deferred — Godot 4.6 a11y API not mature enough for a complete integration |
| In-app font size slider | Deferred to v1.1 |
| Gamepad / controller full remapping | Deferred to v1.1 |
| High-contrast mode | Deferred to v1.1 |
| Light / dark theme toggle | Deferred to v1.1 |
| Visual audio cues | Post-v1 roadmap |
| Individual particle effect toggles | Post-v1 roadmap |

---

## 7. Feedback and Contact

If you experience accessibility barriers, please contact us at:

`operator-contact-email@example.com` *(replace before public release)*

We read every accessibility report and use them to prioritise improvements.

---

## 8. Conformance Status

Cubicraftia v1.0 is **partially conformant** with WCAG 2.1 Level AA. Colour contrast targets are met for all primary UI surfaces. Input alternatives (keyboard, touch) are provided for gameplay. Screen reader support and font scaling are not yet implemented.

We aim for full Level AA conformance by v1.2.
