shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// Blend mode 22, which the puddle's draw sub_41E1C0 sets (0x41E1D5) and the blitters 0x442CD0
// (unscaled) and 0x435B70 (scaled) carry out: skip the colour key; skip where the Z buffer is
// nearer than the base plus the puddle's own Z; then
//   out = (src * a >> 8) + (dst * (255 - a) >> 8)
// with the puddle's alpha byte a. The scaled blitter samples nearest at a step of
// 0x10000 / scale in 8.8 fixed point and reads the Z plane through the same mapping, its values
// unscaled. Nothing writes Z. See docs/player-ability-reference.md, "The puddle".

#include "res://scenes/effects/effect_depth.gdshaderinc"

// The frame's own Z plane, R + 256 G as every -depth.png stores it.
uniform sampler2D depth_plane : filter_nearest, repeat_disable;
// ceil(int(anchor y) / 2): the score of a Z of 0 at the puddle's anchor.
uniform float depth_base = 0.0;
uniform float alpha_byte = 179.0;
// max(1, trunc(scale * 256)).
uniform float scale_units = 256.0;
// ((size - 1) * scale_units >> 8) + 1 pixels each way, which the quad covers.
uniform vec2 drawn_size = vec2(1.0, 1.0);

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 local = min(floor(UV * drawn_size), drawn_size - 1.0);
	float step_size = floor(65536.0 / scale_units);
	vec2 last = vec2(textureSize(TEXTURE, 0) - ivec2(1));
	ivec2 texel = ivec2(clamp(floor(local * step_size / 256.0), vec2(0.0), last));
	vec4 source = texelFetch(TEXTURE, texel, 0);
	if (source.a <= 0.0) {
		discard;
	}
	vec4 encoded = texelFetch(depth_plane, texel, 0);
	float depth = floor(encoded.r * 255.0 + 0.5) + floor(encoded.g * 255.0 + 0.5) * 256.0;
	if (effect_hidden(floor(world_position), depth_base - depth)) {
		discard;
	}
	vec3 rgb = floor(source.rgb * 255.0 + 0.5);
	// Premultiplied, so the destination keeps (255 - a) / 256 of itself as the blitter does.
	COLOR = vec4(floor(rgb * alpha_byte / 256.0) / 255.0, (alpha_byte + 1.0) / 256.0);
}
