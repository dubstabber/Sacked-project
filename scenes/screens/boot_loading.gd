extends Control

# The original's screen 2, the only loading screen it has and the first it shows
# (docs/shell-reference.md). sub_403E20 is its whole tick: while the step counter is below
# 100 it adds one and stores counter * 0.01 as the progress, loading an archive on steps 20,
# 40, 60 and 80; once it reads 100 it moves to the main menu. Nothing skips it. The draw
# sub_422750 reveals the full pot LOADING_ITEM1 from the bottom up by clipping its top
# h - h * progress rows, and shows stream frame (int)(progress * 100) % 5 at (400, 300) less
# the frames' own (3, -43) pivot. It blits the stream in mode 6 at a far z (32769, 0x4228A3), so
# the pot and its rising liquid occlude the stream's lower end -- the stream pours in behind
# them. The port draws the Stream node before the Pot to get the same order. Case 2 starts Menu1
# as the screen comes up.
#
# The port has nothing to load here, so the screen only runs its hundred steps. The original
# takes one per rendered frame at the monitor's refresh; the port takes one per 1/60 s, the
# rate it gives every other per-frame rule of the original, so the screen lasts 1.7 s.

const STEP_COUNT := 100
# flt_465308, the float 0.01 the tick multiplies by. The product is stored as a float, which
# rounds most steps just under their hundredth, so the stream usually shows the frame before
# step % 5. The port rounds through a PackedFloat32Array to land on the same frames.
const PROGRESS_STEP := 0.009999999776482582
const STREAM_FRAME_COUNT := 5
# A GUI image's top left, and the stream's draw point less its pivot.
const POT_ORIGIN := Vector2(375, 487)
const STREAM_ORIGIN := Vector2(397, 343)
# sub_422630 swaps the background on the 666th launch, counted in the registry.
const EVIL_LAUNCH := 666

# Each build paints the game's title into the still in its own language. Any other language
# gets the still with the title painted out and draws the title as text. The evil still's
# words are English in both builds. See docs/strings-reference.md.
const BACKGROUNDS := {
	&"pl": preload("res://images/gui/screens/loading.png"),
	&"de": preload("res://images/gui/screens/loading-de.png"),
}
const UNTITLED_BACKGROUND := preload("res://images/gui/screens/loading-untitled.png")
const BACKGROUND_EVIL := preload("res://images/gui/screens/loading_evil.png")
const STREAM_FRAMES: Array[Texture2D] = [
	preload("res://images/gui/screens/stream/piss-000.png"),
	preload("res://images/gui/screens/stream/piss-001.png"),
	preload("res://images/gui/screens/stream/piss-002.png"),
	preload("res://images/gui/screens/stream/piss-003.png"),
	preload("res://images/gui/screens/stream/piss-004.png"),
]

# Off in a check that steps the screen by hand.
@export var advances := true

@onready var _background: TextureRect = $SafeFrame/Background
@onready var _pot: Sprite2D = $SafeFrame/Pot
@onready var _stream: Sprite2D = $SafeFrame/Stream
@onready var _title: Control = $SafeFrame/Title
@onready var _title_name: Label = $SafeFrame/Title/Name
@onready var _title_tagline: Label = $SafeFrame/Title/Tagline

var step := 0
var _clock := 0.0
var _launch := 0


func _ready() -> void:
	# Only the game's own boot counts a launch and starts the music, not a check that mounts
	# the screen.
	if get_tree().current_scene == self:
		var store := get_node_or_null("/root/SettingsStore")
		if store != null:
			_launch = store.count_launch()
		var screens := get_node_or_null("/root/ScreenManager")
		if screens != null:
			screens.enter_boot_screen()
	_match_background_to_language()
	show_step(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _background != null:
		_match_background_to_language()


func _match_background_to_language() -> void:
	var language := StringName(TranslationServer.get_locale().substr(0, 2))
	_background.texture = background_for(_launch, language)
	_title.visible = _background.texture == UNTITLED_BACKGROUND
	# The first painted line is the name and the rest its tagline, as both builds paint it.
	var lines := tr(&"boot.title").split("\n", true, 1)
	_title_name.text = lines[0]
	_title_tagline.text = lines[1] if lines.size() > 1 else ""


func _process(delta: float) -> void:
	_clock += delta
	while _clock >= NPCBrain.ORIGINAL_FRAME_SECONDS:
		_clock -= NPCBrain.ORIGINAL_FRAME_SECONDS
		advance()


# One run of sub_403E20.
func advance() -> void:
	if step >= STEP_COUNT:
		var screens := get_node_or_null("/root/ScreenManager")
		if advances and screens != null:
			set_process(false)
			screens.change_to_main_menu()
		return
	step += 1
	show_step(step)


func show_step(value: int) -> void:
	var progress := progress_at(value)
	var height := _pot.texture.get_height()
	var top := pot_clip(progress, height)
	_pot.region_rect = Rect2(0, top, _pot.texture.get_width(), height - top)
	_pot.position = POT_ORIGIN + Vector2(0, top)
	_stream.texture = STREAM_FRAMES[stream_frame(progress)]


static func background_for(launch: int, language: StringName) -> Texture2D:
	if launch == EVIL_LAUNCH:
		return BACKGROUND_EVIL
	return BACKGROUNDS.get(language, UNTITLED_BACKGROUND)


# game+19048 * 0.01, stored as a float and clamped to 0..1 by the draw.
static func progress_at(value: int) -> float:
	var stored := PackedFloat32Array([float(value) * PROGRESS_STEP])
	return clampf(stored[0], 0.0, 1.0)


# _ftol(h - h * progress): how many rows of the full pot are still clipped away at the top.
static func pot_clip(progress: float, height: int) -> int:
	return int(float(height) - float(height) * progress)


static func stream_frame(progress: float) -> int:
	return int(progress * 100.0) % STREAM_FRAME_COUNT
