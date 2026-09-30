shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// Blend mode 46, which CSfxSmoke's draw sets (sub_426B60, 0x426B74) and 0x453E20 carries out:
// skip Strings' colour key, black; skip where the Z buffer is nearer; then
//   out = ((255 - a) * dst >> 8) + ((a * ((src * tint) >> 8)) >> 8)
// with the sprite's own alpha a. It reads neither the global alpha nor the weight, so a
// particle never fades, and it never writes Z. See docs/player-ability-reference.md.
//
// One instance per particle: INSTANCE_CUSTOM carries the frame, the particle's depth score,
// its scale in 1/256 units and the pixels its 64 x 64 frame covers; the instance colour is
// the tint. The depth test is scenes/effects/effect_depth.gdshaderinc.

uniform sampler2DArray frames : filter_nearest, repeat_disable;
#include "res://scenes/effects/effect_depth.gdshaderinc"

varying vec2 world_position;
varying flat vec4 particle;
varying flat vec3 tint;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	particle = INSTANCE_CUSTOM;
	tint = floor(COLOR.rgb * 255.0 + 0.5);
}

void fragment() {
	// The blitter samples nearest at a step of 0x10000 / scale, in 8.8 fixed point.
	float width = particle.w;
	float step_size = floor(65536.0 / particle.z);
	vec2 local = min(floor(UV * width), vec2(width - 1.0));
	ivec2 texel = ivec2(clamp(floor(local * step_size / 256.0), vec2(0.0), vec2(63.0)));
	vec4 source = texelFetch(frames, ivec3(texel, int(particle.x)), 0);
	float a = floor(source.a * 255.0 + 0.5);
	vec3 rgb = floor(source.rgb * 255.0 + 0.5);
	if (a <= 0.0 || rgb.r + rgb.g + rgb.b <= 0.0) {
		discard;
	}
	if (effect_hidden(floor(world_position), particle.y)) {
		discard;
	}
	vec3 lit = floor(a * floor(rgb * tint / 256.0) / 256.0);
	// Premultiplied, so the destination keeps (255 - a) / 256 of itself as the blitter does.
	COLOR = vec4(lit / 255.0, (a + 1.0) / 256.0);
}
