shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// sub_4584D0's averaging branch, which sub_41D500's weight of 0 selects: a gradient bilinear in
// 12-bit fixed point over the clipped rectangle, each row stepping 4096 / height and each column
// 4096 / width, both truncated, and
//   dst = ((dst >> 1) & 7F7F7Fh) + ((gradient >> 1) & 7F7F7Fh)
// with nothing written to Z. The corners are bytes 0, 1 and 2 of the four dwords, which the back
// buffer holds as R, G and B. See docs/player-ability-reference.md, "The overlay".

// The canvas in logical pixels, which the screen's UV is spread over.
uniform vec2 canvas_size = vec2(800.0, 600.0);
// The world pass's clip: its first column and row, and how many of each.
uniform vec4 clip = vec4(1.0, 1.0, 799.0, 509.0);
// The clip's size on the original's 800 x 600, which the steps come from. A wider or taller clip
// is spread over it, so the corner colours stay at the corners. See "The overlay in the port".
uniform vec2 original_clip = vec2(799.0, 509.0);
uniform vec3 top_left = vec3(0.0);
uniform vec3 top_right = vec3(0.0);
uniform vec3 bottom_left = vec3(0.0);
uniform vec3 bottom_right = vec3(0.0);
uniform float fixed_one = 4096.0;

void fragment() {
	vec2 pixel = floor(SCREEN_UV * canvas_size);
	// The port's world runs to the canvas edges, past the clip; there the nearest row and column
	// of the gradient go on. See "The overlay in the port".
	float column = clamp(pixel.x - clip.x, 0.0, clip.z - 1.0);
	float row = clamp(pixel.y - clip.y, 0.0, clip.w - 1.0);
	// In integers, so the original's own clip maps every column and row onto itself.
	int original_columns = int(original_clip.x) - 1;
	int original_rows = int(original_clip.y) - 1;
	column = float(int(column) * original_columns / max(int(clip.z) - 1, 1));
	row = float(int(row) * original_rows / max(int(clip.w) - 1, 1));
	float step_x = floor(fixed_one / original_clip.x);
	float step_y = floor(fixed_one / original_clip.y);
	vec3 left = top_left + floor((bottom_left - top_left) * step_y * row / fixed_one);
	vec3 right = top_right + floor((bottom_right - top_right) * step_y * row / fixed_one);
	vec3 gradient = left + floor((right - left) * step_x * column / fixed_one);
	// Premultiplied: the scene keeps half of itself and the gradient adds its halved bytes.
	COLOR = vec4(floor(gradient / 2.0) / 255.0, 0.5);
}
