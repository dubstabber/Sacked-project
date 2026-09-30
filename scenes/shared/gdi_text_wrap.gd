extends RefCounted

# sub_42B9A0's word wrap, for the texts whose breaks a Label's own autowrap would move. A
# Label wraps every line against one width and counts the blank after a word; the original
# does neither. See "Fonts" > "Layout" in docs/hud-reference.md.
#
# sub_42B520 cuts the string into runs of blanks (9, 10 and 32 only) and runs of everything
# else. Before drawing a run, sub_42B9A0 compares its widest line (sub_42BCD0) with the room
# left on the current line; at or past it, the run starts a new line and loses one leading
# blank (0x42BAE6-0x42BB10). The first line's room is the clip width less the start offset
# (0x42BAB6-0x42BAC0); every later line, after a wrap or a line feed, gets the whole clip width
# again while still starting at that offset (0x42BB08, 0x42BBAD). A carriage return is no
# blank: it is a 1-pixel glyph (sub_42B680 gives every character below 0x20 a width of 1), so
# the word before a CRLF of a text file is one pixel wider.

const CR_WIDTH := 1.0


# Returns `text` with a line feed wherever the original breaks it, for a text that starts some
# pixels into a clip rect: `first_room` is the clip width less that start, `room` the whole
# clip width. Every line feed already in `text` is read as the CRLF it was in the original's
# file when `from_crlf_file` is set.
static func break_lines(text: String, font: Font, font_size: int, first_room: float, room: float, from_crlf_file := false) -> String:
	var source := text.replace("\n", "\r\n") if from_crlf_file else text
	var result := ""
	var line := ""
	var limit := first_room
	for run in _runs(source):
		var drawn := run
		if _reach(line, run, font, font_size) >= limit:
			if _is_blank(run[0]):
				drawn = run.substr(1)
			result += "\n"
			line = ""
			limit = room
		for character in drawn:
			if character == "\n":
				result += "\n"
				line = ""
				limit = room
				continue
			line += character
			if character != "\r":
				result += character
	return result


static func _runs(text: String) -> PackedStringArray:
	var runs := PackedStringArray()
	var start := 0
	for index in range(1, text.length() + 1):
		if index == text.length() or _is_blank(text[index]) != _is_blank(text[start]):
			runs.append(text.substr(start, index - start))
			start = index
	return runs


static func _is_blank(character: String) -> bool:
	return character == " " or character == "\n" or character == "\t"


# How far the line would reach with the run on it. sub_42B9A0 subtracts each glyph's integer
# width from the room as it draws; the port measures the line as the Label will draw it, so
# the rounding remainders the face carries are counted the same way.
static func _reach(line: String, run: String, font: Font, font_size: int) -> float:
	if not run.contains("\n"):
		return _width(line + run, font, font_size)
	return _width(line, font, font_size) + _widest_line(run, font, font_size)


# sub_42BCD0: the widest of the run's lines.
static func _widest_line(run: String, font: Font, font_size: int) -> float:
	var widest := 0.0
	for part in run.split("\n"):
		widest = maxf(widest, _width(part, font, font_size))
	return widest


static func _width(text: String, font: Font, font_size: int) -> float:
	var crs := text.count("\r")
	var drawn := text.replace("\r", "")
	var width := font.get_string_size(drawn, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if drawn != "" else 0.0
	return width + CR_WIDTH * crs
