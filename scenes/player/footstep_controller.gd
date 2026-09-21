extends AudioStreamPlayer


@export var stream_path: String = ""
@export var loop_end_seconds: float = 0.0

var footstep_loop_active: bool = false


func _ready() -> void:
	bus = &"SFX"
	if stream_path != "":
		load_footstep_stream()


func configure(path: String, loop_end: float) -> void:
	stream_path = path
	loop_end_seconds = loop_end
	load_footstep_stream()


func load_footstep_stream() -> void:
	if stream_path == "":
		stream = null
		return

	var footstep_stream := AudioStreamWAV.load_from_file(stream_path)
	if footstep_stream == null:
		push_warning("Unable to load footstep stream: %s" % stream_path)
		return

	var loop_end_frame := int(round(loop_end_seconds * footstep_stream.mix_rate))
	footstep_stream.loop_begin = 0
	footstep_stream.loop_end = clampi(loop_end_frame, 1, int(round(footstep_stream.get_length() * footstep_stream.mix_rate)))
	footstep_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

	stream = footstep_stream


func start_footsteps() -> void:
	if stream == null:
		return
	if footstep_loop_active:
		return
	play()
	footstep_loop_active = true


func stop_footsteps() -> void:
	footstep_loop_active = false
	if playing:
		stop()
