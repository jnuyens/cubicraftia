// SPDX-FileCopyrightText: 2026 Cubicraftia contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// title_bg_pan.gdshader — Canvas item shader for the title screen background.
//
// UV pan at 0.002 units/s driven by title_scene._process(delta).
// The uv_offset uniform is updated each frame by:
//   _bg_material.set_shader_parameter("uv_offset",
//       _bg_material.get_shader_parameter("uv_offset") + Vector2(0.002, 0.0) * delta)
//
// Background texture (TextureRect): res://assets/textures/title_bg_bricks.png
// If no texture is assigned the fragment outputs solid navy (fallback colour).

shader_type canvas_item;

uniform vec2 uv_offset = vec2(0.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV + uv_offset);
	// Fallback to solid navy (#0C1532) when texture is unassigned or fully transparent.
	// mix(navy, col, col.a) ensures alpha=0 (no texture) → navy, alpha=1 → textured.
	COLOR = mix(vec4(0.047, 0.082, 0.196, 1.0), col, col.a);
}
