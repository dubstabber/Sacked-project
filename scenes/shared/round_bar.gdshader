shader_type canvas_item;
render_mode unshaded;

// CGUIRoundBarTex::Draw (sub_45AEE0) sweeps a triangle fan rather than clipping a rectangle.
// Every vertex sits at (cx + r * sin a, cy - r * cos a) and samples the texture at
// ((sin a + 1) * r, r - r * cos a), so the texture's top-left 2r x 2r texels are painted
// over a disc of radius r *centred on the element's own position*, and nothing outside that
// disc is drawn. The sweep starts at this+1140 radians and runs clockwise over
// progress * 6.28 + 0.01. See docs/hud-reference.md.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 36.0;
uniform float start_angle = 0.0;

void fragment() {
	vec2 offset = UV * vec2(textureSize(TEXTURE, 0)) - vec2(radius);
	if (length(offset) > radius) {
		discard;
	}
	float angle = mod(atan(offset.x, -offset.y) - start_angle, 6.28318530718);
	if (angle > progress * 6.28 + 0.01) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
