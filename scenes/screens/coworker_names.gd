extends Control

# The original's screen 13, `CCoworkerSetup` (built by sub_41FFC0 through sub_4079C0,
# answered by sub_403F20 case 13). One pool of names at a time: the pool's portrait between
# two arrows, and a name box per record -- one for the boss, the secretary and the janitor,
# three for each coworker variant (sub_420870). The arrows cycle the seven pools, wrapping,
# and Domyślne puts the shown pool's shipped names back. Every button first saves the shown
# boxes, as sub_4082E0 does before it writes NAMES.DAT; typing alone saves nothing.
# See docs/names-reference.md.
#
# Names are proper nouns, so no box or shadow goes through tr().

const BOX_COUNT := 3
const PORTRAIT_PATH := "res://images/gui/menu/portrait-%s.png"

@onready var _store: Node = get_node_or_null("/root/SettingsStore")
@onready var _screens: Node = get_node_or_null("/root/ScreenManager")
@onready var _portrait: TextureRect = $SafeFrame/Portrait

var _index := 0
var _boxes: Array[LineEdit] = []
var _shadows: Array[Label] = []
var _frames: Array[TextureRect] = []


func _ready() -> void:
	for i in BOX_COUNT:
		var box := $SafeFrame.get_node("NameBox%d" % i) as LineEdit
		box.max_length = CoworkerNames.max_length()
		box.text_changed.connect(_on_text_changed.bind(i))
		_boxes.append(box)
		_shadows.append($SafeFrame.get_node("NameShadow%d" % i) as Label)
		_frames.append($SafeFrame.get_node("NameFrame%d" % i) as TextureRect)
	($SafeFrame/Next as TextureButton).pressed.connect(_step.bind(1))
	($SafeFrame/Previous as TextureButton).pressed.connect(_step.bind(-1))
	($SafeFrame/Defaults as TextureButton).pressed.connect(_on_defaults_pressed)
	($SafeFrame/MainMenu as TextureButton).pressed.connect(_on_main_menu_pressed)
	# sub_4079C0 opens on the boss with the first box holding the focus.
	_show(0)
	_boxes[0].grab_focus()


func shown_type() -> int:
	return _index + 1


func _show(index: int) -> void:
	_index = posmod(index, CoworkerNames.type_count())
	var type := shown_type()
	_portrait.texture = load(PORTRAIT_PATH % String(CoworkerNames.profile_id(type)))
	var names := _names_for(type)
	for i in BOX_COUNT:
		var shown := i < names.size()
		# A CGUIInput draws its own frame, so a hidden box takes its frame with it.
		_boxes[i].visible = shown
		_shadows[i].visible = shown
		_frames[i].visible = shown
		_set_box(i, names[i] if shown else "")


func _names_for(type: int) -> PackedStringArray:
	if _store != null:
		return _store.names_for_type(type)
	return CoworkerNames.defaults_for(type)


func _set_box(i: int, text: String) -> void:
	_boxes[i].text = text
	_shadows[i].text = text


func _save_shown() -> void:
	if _store == null:
		return
	var names := PackedStringArray()
	for i in CoworkerNames.pool_size(shown_type()):
		names.append(_boxes[i].text)
	_store.set_names_for_type(shown_type(), names)


# Ids 1 and 2: save the shown pool, then show the next or previous one, wrapping 6 to 0.
func _step(direction: int) -> void:
	_save_shown()
	_show(_index + direction)


# Id 3, sub_415CA0: the shown pool only, and anything typed into it is discarded.
func _on_defaults_pressed() -> void:
	if _store != null:
		_store.reset_names_for_type(shown_type())
	_show(_index)


# Id 4: save, then screen 3.
func _on_main_menu_pressed() -> void:
	_save_shown()
	if _screens != null:
		_screens.change_to_main_menu()


# sub_45C880 refuses ß and takes every other printable key as typed.
func _on_text_changed(text: String, i: int) -> void:
	if text.contains("ß"):
		var caret := _boxes[i].caret_column
		var before := text.length()
		text = text.replace("ß", "")
		_boxes[i].text = text
		_boxes[i].caret_column = maxi(0, caret - (before - text.length()))
	_shadows[i].text = text
