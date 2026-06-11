// creature_wobble.gdshader
//
// Vertex-deform shader used by ShaderWobbleAnimator for single-mesh
// creatures that have no rigid-piece split (slime, fish, ghost, jellyfish,
// snake, manta, etc.).
//
// Three modes selectable via the `body_type` uniform:
//   0 = SLIME    squash + stretch (Y conserve volume), occasional hop
//   1 = FISH     tail-sway: travelling sine wave along the body, more
//                amplitude at the tail end
//   2 = GHOST    vertical float + slight horizontal sway + alpha pulse
//
// Per-instance offsets via `time_offset` so multiple copies don't
// move in lockstep.
//
// Brand-palette gotcha: any tint colour fed to ALBEDO must be LINEAR.
// We never hardcode a colour here -- ALBEDO comes from the mesh's
// vertex/material colour set during the Blender build, which is
// already in linear space because we used hex_to_linear() there.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform int body_type : hint_range(0, 2) = 0;
uniform float wobble_speed : hint_range(0.1, 10.0) = 2.0;
uniform float wobble_amount : hint_range(0.0, 1.0) = 0.20;
uniform float time_offset = 0.0;
uniform vec4 tint : source_color = vec4(1.0);  // multiplicative; default no-op

// Distance along the body's "spine" the tail is from the front.
// For our fish, the head is at +Y, tail at -Y. The constant matches the
// fish_blue mesh extent (~0.20m long).
uniform float spine_length = 0.20;

void vertex() {
    float t = TIME * wobble_speed + time_offset;

    if (body_type == 0) {
        // SLIME -- breathing squash. Scale Y by (1 + amp*sin), and
        // counter-scale X/Z to preserve apparent volume so it reads as
        // a jelly blob rather than a balloon.
        float s = sin(t);
        float vy = 1.0 + s * wobble_amount;
        float vxz = 1.0 / sqrt(max(vy, 0.001));
        VERTEX.y *= vy;
        VERTEX.x *= vxz;
        VERTEX.z *= vxz;
        // little upward hop on every other phase
        float hop = max(0.0, sin(t * 0.5));
        VERTEX.y += hop * 0.05 * wobble_amount;

    } else if (body_type == 1) {
        // FISH -- travelling sine wave along the body. Tail end (-Y)
        // gets full amplitude, head end (+Y) gets none.
        // factor goes from 0 at head to 1 at tail.
        float along = (spine_length * 0.5 - VERTEX.y) / spine_length;
        along = clamp(along, 0.0, 1.0);
        float wave = sin(t * 2.0 + along * 6.28318);
        VERTEX.x += wave * wobble_amount * along;
        // tiny vertical bob with stride
        VERTEX.z += sin(t * 4.0) * 0.01 * wobble_amount;

    } else {
        // GHOST -- float + sway + scale breathing
        VERTEX.y += sin(t) * wobble_amount * 0.15;
        VERTEX.x += sin(t * 0.7) * wobble_amount * 0.05;
        float br = 1.0 + sin(t * 1.3) * 0.04;
        VERTEX.x *= br;
        VERTEX.z *= br;
    }
}

void fragment() {
    // `tint` is the body's brand colour, passed in by the animator as a
    // LINEAR-space Color (matches the Blender pipeline). Godot Colors
    // already live in linear when used in shaders, so no extra
    // conversion needed here.
    ALBEDO = tint.rgb;
    if (body_type == 2) {
        // ghost alpha pulse -- semi-transparent ethereal look
        float pulse = 0.55 + sin(TIME * 1.3 + time_offset) * 0.15;
        ALPHA = pulse;
    } else {
        ALPHA = 1.0;
    }
    METALLIC = 0.0;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
