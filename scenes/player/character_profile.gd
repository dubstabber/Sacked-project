class_name CharacterProfile
extends Resource


@export var id: StringName
@export_range(0.0, 20.0, 0.1, "suffix:tiles/s") var walk_speed_tiles: float = 3.0
# Agent offset +1744; sub_417320 only walks over to an agent of the other gender.
@export_enum("male", "female") var gender: int = 0
@export var animation_library: AnimationLibrary
@export var action_animation_library: AnimationLibrary
@export var idle_animation_prefix: String = ""
@export var walk_animation_prefix: String = ""
@export var initial_texture: Texture2D
@export var footstep_stream_path: String = ""
@export var footstep_loop_end_seconds: float = 0.0
