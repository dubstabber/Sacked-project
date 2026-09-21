shader_type canvas_item;
render_mode unshaded;

// CGUIRoundBarTex sweeps its texture instead of clipping it. The engine's own circle helper
// (sub_45A9E0) places points at x = cx + sin a * r, y = cy - cos a * r, so the sweep starts
// at the top and runs clockwise. See docs/hud-reference.md.

uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 offset = UV - vec2(0.5);
	float angle = atan(offset.x, -offset.y);
	if (angle < 0.0) {
		angle += 6.28318530718;
	}
	if (angle > progress * 6.28318530718) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
