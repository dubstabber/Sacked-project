shader_type canvas_item;
render_mode unshaded;

// The second draw the original makes over an item the cursor is over: Main_RenderUpdate draws
// the item normally, then draws it again in mode 54 (sub_43B050). That pass is a brightened,
// tinted copy of the sprite blended over what is already there at a fixed weight, not an
// additive wash: out_i = (c_i * w + dst_i * (255 - w)) >> 8, where c_i = min(255,
// (sprite_i * tint_i >> 8) + brightness). The weight w is item+7 -- 180 for an object
// (0x403431-0x40343D, 0x403449-0x403455, 0x4033b0-0x403455), 200 for a colleague
// (0x403258-0x40326D) -- and the brightness is 120 + 80*sin(2.5 * phase), truncated, between
// 40 and 200 (0x411EFF, 0x402A7A). The item itself is never modulated and never goes
// transparent; only this copy pulses. `weight` and `brightness` arrive from
// prank_controller.gd as 0..1, so COLOR.rgb carries the tint and the normal blend does the
// mix. See "How the highlight is drawn" in docs/player-action-reference.md.
//
// The depth test is the same one characters use, so the pulse only reaches the pixels where
// the object is actually visible. Underneath, the object is either baked into the static
// world composite or, while a looping clip runs, drawn as a depth-tested actor. An object
// drawn as an actor that overlaps a character is drawn on the character compositor's CPU
// surface instead, so the pass tests that surface's scores as well: the original's copy is
// Z-buffered right after the item (sub_411E20), so a character standing in front of it is
// never lit.

uniform sampler2D depth_map : filter_nearest, repeat_disable;
uniform sampler2D world_depth : filter_nearest, repeat_disable;
uniform vec2 world_depth_origin = vec2(0.0, 0.0);
uniform vec2 world_depth_size = vec2(0.0, 0.0);
uniform sampler2D cluster_depth : filter_nearest, repeat_disable;
uniform vec2 cluster_depth_origin = vec2(0.0, 0.0);
uniform vec2 cluster_depth_size = vec2(0.0, 0.0);
uniform float base_y = 0.0;
uniform vec2 pixel_snap = vec2(0.0, 0.0);
uniform bool depth_map_enabled = false;
uniform bool world_depth_enabled = false;
uniform bool cluster_depth_enabled = false;
// item+7 as 0..1 (180/255 object, 200/255 colleague), and the pulsing lift 120+80*sin(2.5 t).
uniform float weight = 0.0;
uniform float brightness = 0.0;

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
		float score = base_y - (floor(encoded.r * 255.0 + 0.5) + floor(encoded.g * 255.0 + 0.5) * 256.0);
		if (world_depth_enabled) {
			vec2 texel = floor(world_position) - world_depth_origin;
			if (texel.x >= 0.0 && texel.y >= 0.0 && texel.x < world_depth_size.x && texel.y < world_depth_size.y) {
				// A baked object put these very scores in the buffer, so a tie is its own pixel;
				// an actor is tested against what the world has in front of it.
				if (score < texture(world_depth, (texel + 0.5) / world_depth_size).r) {
					discard;
				}
			}
		}
		if (cluster_depth_enabled) {
			vec2 cell = floor(world_position) - cluster_depth_origin;
			if (cell.x >= 0.0 && cell.y >= 0.0 && cell.x < cluster_depth_size.x && cell.y < cluster_depth_size.y) {
				// Likewise here: the surface was composed from this object's own scores.
				if (score < texture(cluster_depth, (cell + 0.5) / cluster_depth_size).r) {
					discard;
				}
			}
		}
	}
	// The brightened, tinted copy, blended over the destination at the fixed weight. The normal
	// (non-additive) blend turns weight * source.a into mix(dst, c, weight) where the sprite is
	// opaque, which is the original's (c*w + dst*(255-w)) >> 8.
	vec3 c = min(vec3(1.0), source.rgb * COLOR.rgb + vec3(brightness));
	COLOR = vec4(c, weight * source.a);
}
