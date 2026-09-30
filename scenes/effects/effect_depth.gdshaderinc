// The Z test an effect the player spawned makes when the effects pass draws it (Main_RenderUpdate,
// 0x402B38): its score against the Z the walls, the items and the characters wrote, larger being
// nearer. A tie draws, as the blitters' `zbuffer >= z` does, and nothing is written. The world
// composite stands in for the walls and items, and each overlapping actor's own depth plane for
// the characters, as scenes/effects/effect_depth.gd hands them over; the tests are the ones
// scenes/shared/character_depth.gdshader makes. See docs/map-rendering.md.

uniform sampler2D world_depth : filter_nearest, repeat_disable;
uniform vec2 world_depth_origin = vec2(0.0, 0.0);
uniform vec2 world_depth_size = vec2(0.0, 0.0);
uniform bool world_depth_enabled = false;
uniform sampler2D actor_depth_0 : filter_nearest, repeat_disable;
uniform sampler2D actor_depth_1 : filter_nearest, repeat_disable;
uniform sampler2D actor_depth_2 : filter_nearest, repeat_disable;
uniform sampler2D actor_depth_3 : filter_nearest, repeat_disable;
uniform sampler2D actor_depth_4 : filter_nearest, repeat_disable;
uniform sampler2D actor_depth_5 : filter_nearest, repeat_disable;
uniform vec4 actor_rect[6];
uniform float actor_base[6];
uniform int actor_count = 0;

// Whether a character's own pixel here is nearer than the effect. Its depth plane has alpha
// exactly where its sprite does.
bool actor_in_front(sampler2D depth_map, vec4 rect, float base, vec2 pixel, float score) {
	vec2 texel = pixel - rect.xy;
	if (texel.x < 0.0 || texel.y < 0.0 || texel.x >= rect.z || texel.y >= rect.w) {
		return false;
	}
	vec4 encoded = texture(depth_map, (texel + 0.5) / rect.zw);
	if (encoded.a <= 0.0) {
		return false;
	}
	float depth = floor(encoded.r * 255.0 + 0.5) + floor(encoded.g * 255.0 + 0.5) * 256.0;
	return score < base - depth;
}

// Whether the effect's pixel at this world pixel, with this score, is behind something drawn.
bool effect_hidden(vec2 pixel, float score) {
	if (world_depth_enabled) {
		vec2 cell = pixel - world_depth_origin;
		if (cell.x >= 0.0 && cell.y >= 0.0 && cell.x < world_depth_size.x && cell.y < world_depth_size.y) {
			if (score < texture(world_depth, (cell + 0.5) / world_depth_size).r) {
				return true;
			}
		}
	}
	if (actor_count > 0 && actor_in_front(actor_depth_0, actor_rect[0], actor_base[0], pixel, score)) {
		return true;
	}
	if (actor_count > 1 && actor_in_front(actor_depth_1, actor_rect[1], actor_base[1], pixel, score)) {
		return true;
	}
	if (actor_count > 2 && actor_in_front(actor_depth_2, actor_rect[2], actor_base[2], pixel, score)) {
		return true;
	}
	if (actor_count > 3 && actor_in_front(actor_depth_3, actor_rect[3], actor_base[3], pixel, score)) {
		return true;
	}
	if (actor_count > 4 && actor_in_front(actor_depth_4, actor_rect[4], actor_base[4], pixel, score)) {
		return true;
	}
	if (actor_count > 5 && actor_in_front(actor_depth_5, actor_rect[5], actor_base[5], pixel, score)) {
		return true;
	}
	return false;
}
