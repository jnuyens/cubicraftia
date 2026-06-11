// SPDX-FileCopyrightText: 2026 Cubicraftia contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// brick_terrain.gdshader — Lego-style stud shader for VoxelMesherBlocky terrain.
//
// Every UP-FACING block surface shows a 2×2 grid of cylinder studs. The studs use
// PARALLAX OCCLUSION MAPPING so they look genuinely raised (real depth + silhouette and
// occlusion at grazing angles) with NO extra geometry — mobile-safe (a short per-fragment
// ray-march only on top faces; sides/bottoms render flat).
//
// Studs sit on a world-space grid so they tile seamlessly across blocks and chunks.
// The mesher's baked-AO vertex COLOR is preserved (multiplied into ALBEDO).

shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float stud_pitch = 0.5;     // world spacing between studs (0.5 m = 2×2 per block)
uniform float stud_radius = 0.15;   // stud radius (m); < pitch/2 leaves a gap
// Parallax can only carve INWARD (never above the polygon), so a deep value made the
// studded top sit in a well below the block's side rim. Keep it shallow so the stud
// tops stay flush with the block top / side edges and the gaps only dip slightly.
uniform float stud_height = 0.05;   // parallax depth of the inter-stud gap (m)
uniform int   pom_steps = 12;       // parallax march steps (quality vs cost)

varying vec3 v_world_pos;
varying vec3 v_world_normal;

// Height field of the stud surface at a world XZ position: 1.0 on a stud top,
// 0.0 on the recessed base plate, with a short ramp at the rim.
float stud_height_at(vec2 wxz) {
	vec2 centre = (floor(wxz / stud_pitch) + 0.5) * stud_pitch;
	float d = length(wxz - centre);
	return 1.0 - smoothstep(stud_radius * 0.8, stud_radius, d);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ROUGHNESS = 1.0;
	METALLIC = 0.0;

	if (v_world_normal.y <= 0.5) {
		// Sides + bottoms: flat textured block faces, exactly as before.
		ALBEDO = texture(atlas, UV).rgb * COLOR.rgb;
	} else {
		// ── Parallax occlusion march over the stud height field (top faces) ──────
		// View direction from the camera into the surface, in world space.
		vec3 view_w = normalize(v_world_pos - CAMERA_POSITION_WORLD);
		float down = max(-view_w.y, 0.06);              // how steeply we look onto the top
		// XZ distance the ray travels per unit of height descended.
		vec2 step_xz = (view_w.xz / down) * stud_height / float(pom_steps);

		float layer_h = 1.0 / float(pom_steps);         // height removed per step (normalised)
		float ray_h = 1.0;                              // start at the stud-top plane
		vec2 sample_xz = v_world_pos.xz;
		float surf = stud_height_at(sample_xz);
		// Walk down until the height field rises to meet the view ray.
		for (int i = 0; i < pom_steps; i++) {
			if (surf >= ray_h) {
				break;
			}
			ray_h -= layer_h;
			sample_xz += step_xz;
			surf = stud_height_at(sample_xz);
		}

		// Normal from the height-field gradient → rounded cylinder shading.
		float e = 0.015;
		float gx = stud_height_at(sample_xz + vec2(e, 0.0)) - stud_height_at(sample_xz - vec2(e, 0.0));
		float gz = stud_height_at(sample_xz + vec2(0.0, e)) - stud_height_at(sample_xz - vec2(0.0, e));
		float slope = stud_height / (2.0 * e);
		vec3 wn = normalize(vec3(-gx * slope, 1.0, -gz * slope));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

		// Albedo: sample the atlas (top tile is near-uniform, so the parallax XZ shift
		// barely changes the colour); shade the recessed base plate a touch darker.
		float on_stud = stud_height_at(sample_xz);
		ALBEDO = texture(atlas, UV).rgb * COLOR.rgb * mix(0.78, 1.06, on_stud);
	}
}
