extends RefCounted

# CGUIInput (vtable 0x4674DC), the original's text box, which screen 12's name box and screen
# 13's coworker-name boxes both are. The port draws each as a LineEdit and a Label: sub_45CE00
# draws a (32, 32, 32) copy of the text two pixels right and down behind it, and a LineEdit draws
# none, so the label mirrors the text. See "Names are editable" in docs/names-reference.md.
#
# sub_45CE00 starts centred text at x = (w - text width) / 2 - 2 (0x45CEE1-0x45CEF0), two pixels
# left of the true centre, and at y = (h - cell) / 2, so its copy, at (x + 2, y + 2), is the one
# that is centred across. A LineEdit centres exactly and takes no right margin into account, so
# each box's LineEdit sits CENTRE_SHIFT to the left of the box's rect, and its copy label over
# the rect itself, two pixels down.
const CENTRE_SHIFT := -2.0


# The key handler, sub_45C880 (vtable slot +0x44), refuses ß and types every other printable key.
# Returns what is left in the box, which the copy mirrors.
static func take_text(edit: LineEdit, copy: Label, text: String) -> String:
	if text.contains("ß"):
		var caret := edit.caret_column
		var before := text.length()
		text = text.replace("ß", "")
		edit.text = text
		edit.caret_column = maxi(0, caret - (before - text.length()))
	copy.text = text
	return text


# A box filled from code, and its copy with it.
static func show_text(edit: LineEdit, copy: Label, text: String) -> void:
	edit.text = text
	copy.text = text
