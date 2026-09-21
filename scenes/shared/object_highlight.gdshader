shader_type canvas_item;
render_mode unshaded, blend_add;

// The second draw the original makes over an item the cursor is over: Main_RenderUpdate
// draws the item normally, then draws it again tinted from item+4..6 with an alpha that
// swings between 40 and 200. The item itself never goes transparent -- this pass only adds
// to it, which is what makes the highlight pulse. See docs/player-action-reference.md.
//
// The depth test is the same one characters use, so the pulse only reaches the pixels where
// the object is actually visible; the object stays in the static world composite underneath.

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
			float depth = floor(encoded.r * 255.0 + 0.5) + floor(encoded.g * 255.0 + 0.5) * 256.0;
			vec2 texel = floor(world_position) - world_depth_origin;
			if (texel.x >= 0.0 && texel.y >= 0.0 && texel.x < world_depth_size.x && texel.y < world_depth_size.y) {
				// The object put these very scores in the buffer, so a tie is its own pixel.
				if (base_y - depth < texture(world_depth, (texel + 0.5) / world_depth_size).r) {
					discard;
				}
			}
		}
	}
	COLOR = vec4(source.rgb * COLOR.rgb, source.a) * COLOR.a;
}
