// SPDX-FileCopyrightText: 2026 Cubicraftia contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// sky_procedural.gdshader — Procedural sky shader scaffold for Tier-1/Tier-2 hardware.
//
// Consumed by the WorldEnvironment sky material. Plan 06 wires day_progress from
// WorldClock.current_day_progress() and binds the tint uniforms to the WorldEnvironment.
//
// Tier-3 (Motorola-class low-end) falls back to four baked PanoramaSkyMaterial textures
// (Pitfall 11 mitigation). The four panorama placeholders are declared in:
//   assets/textures/sky/{dawn,day,dusk,night}_panorama.png.license
// Actual .png assets are delivered by the art pass before phase-end (Plan 15 verifies).
//
// Cross-fade logic: smoothstep transitions between the four phase tints. The thresholds
// mirror WorldClock.Phase boundaries:
//   [0.00, 0.05) DAWN
//   [0.05, 0.65) DAY
//   [0.65, 0.70) DUSK
//   [0.70, 1.00) NIGHT
//
// References:
//   02-RESEARCH.md §"Pattern 6: Day/night clock" (sky shader integration)
//   02-RESEARCH.md §"Pitfall 11" (Tier-3 fallback to panorama textures)
//   02-UI-SPEC.md §"Day/Night Sky Visuals"

shader_type sky;

// ─── Uniforms ──────────────────────────────────────────────────────────────

/// Normalised day progress [0.0, 1.0) driven by WorldClock.current_day_progress().
/// Bound per-frame by the WorldEnvironment controller in Plan 06.
uniform float day_progress : hint_range(0.0, 1.0) = 0.5;

/// Sky tint for the DAWN phase (sunrise amber/salmon).
uniform vec4 dawn_tint : source_color = vec4(1.0, 0.7, 0.5, 1.0);

/// Sky tint for the DAY phase — vibrant splash-style blue (horizon tone; the sky()
/// function deepens it toward the zenith for a richer gradient).
uniform vec4 day_tint : source_color = vec4(0.36, 0.66, 0.98, 1.0);

/// Sky tint for the DUSK phase (sunset orange/coral).
uniform vec4 dusk_tint : source_color = vec4(0.950, 0.451, 0.298, 1.0);

/// Sky tint for the NIGHT phase (deep indigo).
uniform vec4 night_tint : source_color = vec4(0.051, 0.051, 0.180, 1.0);

/// Cloud tuning: coverage (lower = more cloud), softness, drift speed, planar scale.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_drift = 0.006;
uniform float cloud_scale = 0.75;

// ─── Procedural value-noise + fbm for the cloud layer ────────────────────────

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

// ─── Sky function ──────────────────────────────────────────────────────────

void sky() {
	// Vertical gradient for a vibrant daytime sky: lighter near the horizon, a deeper,
	// more saturated blue overhead (h = 0 at horizon, 1 at zenith).
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 day_horizon = day_tint.rgb;
	vec3 day_zenith = day_tint.rgb * vec3(0.55, 0.78, 1.04);  // deeper + bluer overhead
	vec3 day = mix(day_horizon, day_zenith, smoothstep(0.0, 0.55, h));

	// Start with the dawn tint, then cross-fade through the phases.
	vec3 colour = dawn_tint.rgb;
	colour = mix(colour, day, smoothstep(0.05, 0.10, day_progress));
	colour = mix(colour, dusk_tint.rgb, smoothstep(0.65, 0.70, day_progress));
	colour = mix(colour, night_tint.rgb, smoothstep(0.70, 0.80, day_progress));

	// ── Cloud layer ──────────────────────────────────────────────────────────
	// Project the view ray onto a high horizontal plane and sample drifting fbm.
	// Only above the horizon; faded out at night. No geometry — pure sky shading.
	if (EYEDIR.y > 0.03) {
		vec2 cuv = (EYEDIR.xz / (EYEDIR.y + 0.30)) * cloud_scale;
		cuv += vec2(TIME * cloud_drift, TIME * cloud_drift * 0.6);
		float n = fbm(cuv);
		float cover = smoothstep(cloud_coverage, cloud_coverage + 0.28, n);
		float horizon_fade = smoothstep(0.03, 0.20, EYEDIR.y);
		float day_amt = clamp(1.0 - smoothstep(0.62, 0.80, day_progress), 0.12, 1.0);
		// Soft white clouds, slightly tinted by the underlying sky for cohesion.
		vec3 cloud_col = mix(vec3(1.0), colour, 0.12);
		colour = mix(colour, cloud_col, cover * horizon_fade * day_amt);
	}

	COLOR = colour;
}
