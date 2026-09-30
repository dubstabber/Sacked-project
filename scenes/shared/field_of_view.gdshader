shader_type canvas_item;
// sub_4298E0 adds each texel to the back buffer with paddusb, a saturating add on every
// byte, and skips a texel of 0. Only the blue byte is ever set, so the texture carries it in
// its one channel. blend_add on the port's 8-bit canvas (hdr_2d is off) saturates the same
// way. Nothing is clipped, as nothing else in the port's world is. See "Clipping" in
// docs/field-of-view-reference.md.
render_mode blend_add, unshaded;

void fragment() {
	float blue = texture(TEXTURE, UV).r;
	if (blue == 0.0) {
		discard;
	}
	COLOR = vec4(0.0, 0.0, blue, 1.0);
}
