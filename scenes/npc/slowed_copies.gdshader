shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// Blend mode 54 on an 8-bpp sprite with a Z plane, the blitter 0x43B050 that sub_417460's green
// copies go through: skip the colour key; skip where the Z buffer is nearer than the copy's own
// Z, the agent's less 2; then per channel
//   c   = min(255, (src * tint >> 8) + brightness)
//   out = (c * weight >> 8) + (dst * (255 - weight) >> 8)
// with nothing written to Z. A plain blend of a brightened tint, not an additive one.
// See docs/player-ability-reference.md, "The green copies".

#include "res://scenes/effects/effect_depth.gdshaderinc"

// The frame's own Z plane, R + 256 G as every -depth.png stores it.
uniform sampler2D depth_plane : filter_nearest, repeat_disable;
uniform bool depth_plane_enabled = false;
// ceil(int(anchor y) / 2) + 2: the score of a Z of 0, two units nearer than the agent's.
uniform float depth_base = 0.0;
uniform vec3 tint = vec3(255.0);
uniform float brightness = 0.0;
uniform float brightness_limit = 255.0;
uniform float weight = 0.0;
uniform float full_weight = 255.0;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (source.a <= 0.0) {
		discard;
	}
	if (depth_plane_enabled) {
		vec4 encoded = texture(depth_plane, UV);
		if (encoded.a <= 0.0) {
			discard;
		}
		float depth = floor(encoded.r * 255.0 + 0.5) + floor(encoded.g * 255.0 + 0.5) * 256.0;
		if (effect_hidden(floor(world_position), depth_base - depth)) {
			discard;
		}
	}
	vec3 rgb = floor(source.rgb * 255.0 + 0.5);
	vec3 lifted = min(floor(rgb * tint / 256.0) + brightness, vec3(brightness_limit));
	// Premultiplied, so the destination keeps (255 - weight) / 256 of itself as the blitter does.
	COLOR = vec4(floor(lifted * weight / 256.0) / 255.0, 1.0 - (full_weight - weight) / 256.0);
}
