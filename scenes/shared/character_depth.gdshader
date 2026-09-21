shader_type canvas_item;
render_mode unshaded;

// GPU equivalent of the original per-pixel SPRITEZB depth test
// (blitters at 0x42E8F0/0x42E9D0/0x42ECC0, docs/graphics/pipeline.md).
// The character keeps its own 16-bit depth plane; the static world depth
// arrives as an R32F score buffer baked by WorldDepthCompositor.

uniform sampler2D depth_map : filter_nearest, repeat_disable;
uniform sampler2D world_depth : filter_nearest, repeat_disable;
uniform vec2 world_depth_origin = vec2(0.0, 0.0);
uniform vec2 world_depth_size = vec2(0.0, 0.0);
uniform float base_y = 0.0;
uniform vec2 pixel_snap = vec2(0.0, 0.0);
uniform bool depth_map_enabled = false;
uniform bool world_depth_enabled = false;

varying vec2 world_position;

void vertex() {
	// The original engine converts projected positions to integers before blitting,
	// so the quad lands on whole pixels instead of sampling between texels.
	VERTEX += pixel_snap;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (source.a <= 0.0) {
		discard;
	}
	if (depth_map_enabled) {
		vec4 encoded = texture(depth_map, UV);
		if (encoded.a <= 0.0) {
			discard;
		}
		if (world_depth_enabled) {
			// Depth is stored low byte in R, high byte in G; see docs/formats/image_format.md.
			float depth = floor(encoded.r * 255.0 + 0.5) + floor(encoded.g * 255.0 + 0.5) * 256.0;
			vec2 texel = floor(world_position) - world_depth_origin;
			if (texel.x >= 0.0 && texel.y >= 0.0 && texel.x < world_depth_size.x && texel.y < world_depth_size.y) {
				if (base_y - depth < texture(world_depth, (texel + 0.5) / world_depth_size).r) {
					discard;
				}
			}
		}
	}
	COLOR = source;
}
