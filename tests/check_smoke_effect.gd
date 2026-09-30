extends SceneTree

# CSfxSmoke, the cigarette smoke smoking spawns: the parameters exported from sacked.exe, the
# emitter, the bursts and their cap, each particle's ramps and drift, its frame, its size on
# screen and its depth score, and what the draw is handed. The random source is fixed, because
# RANMAR's seed is not recovered and only the ranges matter.
# See docs/player-ability-reference.md, "The smoke".

const SMOKE := preload("res://scenes/effects/smoke.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_parameters_are_the_recovered_ones()
	_check_the_emitter_sits_at_the_mouth()
	_check_the_first_tick_advances_nothing()
	_check_a_burst_is_fifty_once_the_accumulator_passes_two()
	_check_the_array_holds_two_hundred()
	_check_a_particle_ramps_and_drifts()
	_check_a_dead_particle_hands_its_slot_to_the_last()
	_check_the_frame_follows_the_particles_own_age()
	_check_the_size_on_screen()
	_check_the_depth_score()
	_check_the_draw_data()
	_check_stop_and_the_whole_life()
	if _failures == 0:
		print("Smoke effect: the exported parameters, the mouth, the bursts and their cap, the ramps and drift, the frame, the size, the depth score, the draw data and the whole life passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _near(a: float, b: float, epsilon := 1.0e-6) -> bool:
	return absf(a - b) <= epsilon


# The particle fields are float32, as the original's are, so a position near 20 holds about
# six decimals.
func _near_f32(a: float, b: float) -> bool:
	return absf(a - b) <= 1.0e-5 * maxf(1.0, absf(b))


func _poke(smoke: Node, index: int, field: int, value: float) -> void:
	smoke.particles[index * SMOKE.STRIDE + field] = value


# One live particle at a chosen place and size, and what the draw is handed for it.
func _drawn_at(smoke: Node, x: float, y: float, z: float, size: float) -> Dictionary:
	smoke.alive = 0
	smoke._emit()
	_poke(smoke, 0, SMOKE.POS_X, x)
	_poke(smoke, 0, SMOKE.POS_Y, y)
	_poke(smoke, 0, SMOKE.POS_Z, z)
	_poke(smoke, 0, SMOKE.SIZE, size)
	smoke._publish()
	return smoke.drawn(0)


# tools/export_smoke_params.py reads these out of sacked.exe and its --check pins them; this
# only proves the file is the one the smoke loads.
func _check_the_parameters_are_the_recovered_ones() -> void:
	var params: Dictionary = SMOKE.params()
	_expect(int(params.get("capacity", 0)) == 200, "the array holds 200")
	_expect(_near(float(params.get("lifetime", 0.0)), 5.0) and _near(float(params.get("interval", 0.0)), 2.0), "a particle lives 5 s and a burst comes every 2 s")
	_expect(_near(float(params.get("per_interval", 0.0)), 25.0), "25 particles an interval")
	var ramps := {
		"speed": [1.2, 0.0, 0.0], "rise": [0.0, -0.1, -6.0], "size": [0.01, 0.01, 0.6],
		"red": [235.0, 10.0, 185.0], "blue": [245.0, 10.0, 195.0], "alpha": [240.0, 1.0, 1.0],
	}
	for ramp: String in ramps:
		var values: Array = params.get(ramp, [])
		var expected: Array = ramps[ramp]
		var matches := values.size() == 3
		for i in range(mini(values.size(), 3)):
			matches = matches and _near(float(values[i]), float(expected[i]), 1.0e-6)
		_expect(matches, "the %s ramp is %s, got %s" % [ramp, expected, values])


func _smoke(value := 0.5) -> Node:
	var smoke := SMOKE.new()
	smoke.random = func() -> float: return value
	root.add_child(smoke)
	return smoke


func _drop(smoke: Node) -> void:
	root.remove_child(smoke)
	smoke.free()


# a = (view * 45 + 180) * 0.017453; 0.21 tiles along the facing, 1.85 units up.
func _check_the_emitter_sits_at_the_mouth() -> void:
	var smoke := _smoke()
	smoke.start(Vector2(10.0, 20.0), 0.0, 0, Vector2.ZERO)
	var a := 180.0 * 0.017453
	_expect(_near_f32(smoke.emitter.x, 10.0 - 0.21 * sin(a)), "view 0's mouth keeps x, got %f" % smoke.emitter.x)
	_expect(_near_f32(smoke.emitter.z, 20.0 + 0.21 * cos(a)) and smoke.emitter.z < 19.8, "view 0 faces -z, got z %f" % smoke.emitter.z)
	_expect(_near_f32(smoke.emitter.y, 1.85), "the mouth is 1.85 units up")
	_expect(_near_f32(smoke.emitter_velocity.z, 0.21 * cos(a)) and _near(smoke.emitter_velocity.y, 0.0), "the velocity points along the facing")

	smoke.start(Vector2(10.0, 20.0), 0.5, 2, Vector2.ZERO)
	_expect(smoke.emitter.x > 10.2 and _near(smoke.emitter.z, 20.0, 1.0e-3), "view 2 faces +x, got %s" % smoke.emitter)
	_expect(_near_f32(smoke.emitter.y, 2.35), "the mouth rises with the player's own height")
	_drop(smoke)


# DeltaTime_Calculate seeds on the first call, so the spawn tick moves nothing.
func _check_the_first_tick_advances_nothing() -> void:
	var smoke := _smoke()
	smoke.start(Vector2(4.0, 4.0), 0.0, 3, Vector2.ZERO)
	smoke._emit()
	var age: float = smoke.particle(0)["age"]
	smoke.tick(37.0)
	_expect(_near(float(smoke.particle(0)["age"]), age) and _near(smoke.accumulator, 0.0), "the first tick's step is zero")
	smoke.tick(37.25)
	_expect(_near(float(smoke.particle(0)["age"]), age + 0.25), "later ticks step by the clock's difference")
	_drop(smoke)


# n = 25 * ceil(acc / 2): 50 once the accumulator has passed 2.0 by a fraction of a frame, and
# 25 only if it lands on 2.0 exactly.
func _check_a_burst_is_fifty_once_the_accumulator_passes_two() -> void:
	var smoke := _smoke()
	smoke.start(Vector2(4.0, 4.0), 0.0, 3, Vector2.ZERO)
	for _i in range(6):
		smoke.advance(0.3)
	_expect(smoke.alive == 0, "nothing is emitted before two seconds")
	smoke.advance(0.3)
	_expect(smoke.alive == 50, "the burst after 2.1 s is 50, got %d" % smoke.alive)
	_expect(_near(smoke.accumulator, 0.0), "a burst empties the accumulator")
	_drop(smoke)

	var exact := _smoke()
	exact.start(Vector2(4.0, 4.0), 0.0, 3, Vector2.ZERO)
	for _i in range(8):
		exact.advance(0.25)
	_expect(exact.alive == 25, "an accumulator of exactly 2.0 emits 25, got %d" % exact.alive)
	_drop(exact)


func _check_the_array_holds_two_hundred() -> void:
	var smoke := _smoke(0.0)
	smoke.start(Vector2(4.0, 4.0), 0.0, 3, Vector2.ZERO)
	smoke.advance(20.0)
	_expect(smoke.alive == 200, "a frame of 20 s asks for 250 and gets 200, got %d" % smoke.alive)
	_drop(smoke)


# With every draw at 0.5: pre-age 0.3, rise -0.05, speed 1.2, size 0.015, tint (240, 240, 250).
func _check_a_particle_ramps_and_drifts() -> void:
	var smoke := _smoke(0.5)
	smoke.start(Vector2(10.0, 20.0), 0.0, 2, Vector2.ZERO)
	var draws := [0]
	smoke.random = func() -> float:
		draws[0] += 1
		return 0.5
	smoke._emit()
	_expect(draws[0] == 8, "a particle draws eight values, got %d" % draws[0])
	var p: Dictionary = smoke.particle(0)
	_expect(_near(p["age"], 0.3) and _near(p["rise0"], -0.05) and _near(p["speed0"], 1.2), "the births follow start + spread * r")
	_expect(_near(p["size0"], 0.015) and _near(p["red0"], 240.0) and _near(p["green0"], 240.0) and _near(p["blue0"], 250.0), "size and tint start in their ranges")
	_expect(_near_f32(p["vx"], 1.4 * smoke.emitter_velocity.x) and _near_f32(p["vz"], 1.4 * smoke.emitter_velocity.z), "every particle gets 1.4 times the emitter's velocity")
	var x0: float = p["x"]
	var y0: float = p["y"]
	var z0: float = p["z"]

	smoke.advance(0.5)
	p = smoke.particle(0)
	var f := 0.2 * 0.8
	_expect(_near(p["age"], 0.8), "the age steps by dt")
	_expect(_near_f32(p["speed"], 1.2 * (1.0 - f)), "speed ramps to 0, got %f" % p["speed"])
	_expect(_near_f32(p["rise"], -0.05 + (-6.0 + 0.05) * f), "the rise ramps to -6, got %f" % p["rise"])
	_expect(_near_f32(p["red"], 240.0 + (185.0 - 240.0) * f) and _near_f32(p["blue"], 250.0 + (195.0 - 250.0) * f), "the tint greys toward (185, 185, 195)")
	_expect(_near_f32(p["size"], 0.015 + (0.6 - 0.015) * f), "the size grows toward 0.6")
	var k := 0.5 * float(p["speed"])
	_expect(_near_f32(p["x"], x0 + k * float(p["vx"])) and _near_f32(p["z"], z0 + k * float(p["vz"])), "x and z move by dt * speed * v")
	_expect(_near_f32(p["y"], y0 - 0.5 * float(p["rise"]) * 0.1), "y climbs by -dt * g * 0.1, got %f" % p["y"])
	_drop(smoke)

	var low := _smoke(0.0)
	low.start(Vector2(10.0, 20.0), -2.0, 2, Vector2.ZERO)
	low._emit()
	low.advance(0.1)
	_expect(_near(float(low.particle(0)["y"]), 0.1), "y is held at 0.1 from below")
	_drop(low)


# sub_4265A0 moves the last particle into the freed slot, and that one is aged in the same
# pass.
func _check_a_dead_particle_hands_its_slot_to_the_last() -> void:
	var smoke := _smoke(0.0)
	smoke.start(Vector2(4.0, 4.0), 0.0, 3, Vector2.ZERO)
	for _i in range(3):
		smoke._emit()
	_poke(smoke, 0, SMOKE.AGE, 4.95)
	_poke(smoke, 2, SMOKE.RED_BIRTH, 111.0)
	smoke.advance(0.1)
	_expect(smoke.alive == 2, "the particle that reached 5.0 is gone")
	_expect(_near(float(smoke.particle(0)["red0"]), 111.0), "the last particle took its slot")
	_expect(_near(float(smoke.particle(0)["age"]), 0.1), "and was aged in the same pass")
	_drop(smoke)


func _check_the_frame_follows_the_particles_own_age() -> void:
	var cases := {0.0: 0, 0.124: 0, 0.125: 1, 0.6: 4, 1.99: 15, 2.0: 0, 4.99: 7}
	for age: float in cases:
		_expect(SMOKE.frame_of(age) == int(cases[age]), "age %f shows frame %d, got %d" % [age, cases[age], SMOKE.frame_of(age)])
	# tools/export_gui_assets.py writes each frame's offset as [-32, -32], the 64 x 64 frame's centre.
	_expect(SMOKE._pivot == Vector2(32.0, 32.0), "the Strings frames share the pivot (32, 32), got %s" % SMOKE._pivot)


# s = max(1, trunc(size * 255)) in 1/256 units, covering ((s * 63) >> 8) + 1 pixels, centred
# on the particle.
func _check_the_size_on_screen() -> void:
	var smoke := _smoke()
	var widths := {0.0: 1, 0.01: 1, 0.02: 2, 0.0808: 5, 0.6: 38}
	for size: float in widths:
		var placed := _drawn_at(smoke, 0.0, 0.0, 0.0, size)
		_expect(int(placed["width"]) == int(widths[size]), "size %f covers %d px, got %d" % [size, widths[size], placed["width"]])
	var big := _drawn_at(smoke, 0.0, 0.0, 0.0, 0.6)
	_expect(int(big["scale"]) == 153, "size 0.6 scales by 153/256")
	smoke.ground_origin = Vector2(100.0, 200.0)
	big = _drawn_at(smoke, 0.0, 0.0, 0.0, 0.6)
	_expect(big["top_left"] == Vector2(80.0, 180.0), "trunc(screen + 32 - 32 size) - 32, got %s" % big["top_left"])
	_drop(smoke)


# 48 px per unit of height, and a score of ceil(int(sy) / 2) - 48, larger being nearer.
func _check_the_depth_score() -> void:
	var smoke := _smoke()
	smoke.ground_origin = Vector2(48.0, 24.0)
	var placed := _drawn_at(smoke, 10.0, 1.85, 20.0, 0.15)
	var sy := 24.0 + 24.0 * 30.0 - 48.0 * 1.85
	var shift := 32.0 - 32.0 * 0.15
	_expect(placed["top_left"].y == floorf(sy + shift) - 32.0, "the particle rises 48 px a unit, got %s" % placed["top_left"])
	_expect(placed["top_left"].x == floorf(48.0 + 48.0 * (10.0 - 20.0) + shift) - 32.0, "x projects as the ground does, got %s" % placed["top_left"])
	_expect(_near(float(placed["score"]), ceilf(float(int(sy)) * 0.5) - 48.0), "score = ceil(int(sy) / 2) - 48, got %f" % placed["score"])
	var ground := _drawn_at(smoke, 10.0, 0.0, 20.0, 0.15)
	_expect(float(ground["score"]) > float(placed["score"]), "height pushes a particle back")
	_drop(smoke)


# One instance per particle in MultiMesh.buffer: a quad one width square at its top left, the
# truncated tint as its colour, and its frame, score, scale and width as custom data. The
# dummy renderer keeps no instance data, so this reads the buffer the draw is handed.
func _check_the_draw_data() -> void:
	var smoke := _smoke(0.5)
	smoke.start(Vector2(10.0, 20.0), 0.0, 2, Vector2(48.0, 24.0))
	smoke._emit()
	smoke._emit()
	smoke.advance(0.5)
	var mesh: MultiMesh = smoke.multimesh
	_expect(mesh != null and mesh.instance_count == 200, "the multimesh holds the array's 200")
	_expect(mesh.visible_instance_count == 2, "two particles, two instances drawn")
	_expect(smoke.instance_buffer.size() == 200 * 16, "the buffer is 16 floats an instance")
	# The canvas keeps the rect of the smoke's first, empty draw; only a fixed box keeps the
	# particles that come later from being culled (seen in a window, not here).
	_expect(mesh.custom_aabb.size.x > 10000.0 and mesh.custom_aabb.size.y > 10000.0, "the multimesh keeps a fixed box, got %s" % mesh.custom_aabb)
	var p: Dictionary = smoke.particle(0)
	var data: Dictionary = smoke.drawn(0)
	var size := float(p["size"])
	var scale := maxi(1, int(size * 255.0))
	# Born 0.3 s old (0.6 times the source's 0.5) and aged half a second: 0.8 s at the Strings
	# clip's 8 fps is frame 6 of its 16.
	_expect(_near(float(p["age"]), 0.8, 1.0e-6) and int(data["frame"]) == 6, "the instance carries the particle's frame, 6 at 0.8 s, got %d at %f" % [int(data["frame"]), float(p["age"])])
	_expect(int(data["scale"]) == scale and int(data["width"]) == ((scale * 63) >> 8) + 1, "and its scale and width")
	var screen := Vector2(48.0, 24.0) + IsoDirection.ground_to_screen(Vector2(float(p["x"]), float(p["z"]))) - Vector2(0.0, 48.0 * float(p["y"]))
	_expect(_near(float(data["score"]), ceilf(float(int(screen.y)) * 0.5) - 48.0), "and its depth score")
	var shift := 32.0 - 32.0 * size
	_expect(data["top_left"] == Vector2(floorf(screen.x + shift), floorf(screen.y + shift)) - Vector2(32.0, 32.0), "the quad sits at the top left, got %s" % data["top_left"])
	var buffer: PackedFloat32Array = smoke.instance_buffer
	var width := float(data["width"])
	_expect(
		_near(buffer[0], width) and _near(buffer[5], width) and _near(buffer[1], 0.0) and _near(buffer[4], 0.0),
		"one width square, with no rotation"
	)
	var tint: Color = data["tint"]
	_expect(_near(tint.r, floor(float(p["red"])) / 255.0, 1.0e-5), "the tint is trunc(c0), got %f" % tint.r)
	_expect(_near(tint.b, floor(float(p["blue"])) / 255.0, 1.0e-5), "and trunc(c2) in blue")
	var both := Rect2(data["top_left"], Vector2.ONE * width).merge(Rect2(smoke.drawn(1)["top_left"], Vector2.ONE * float(smoke.drawn(1)["width"])))
	_expect(smoke.drawn_bounds == both, "the bounds the depth test looks at are the quads just drawn")
	_expect(smoke.z_index == 3, "the smoke draws after the characters, bubbles and names")
	_drop(smoke)


# From the spawn: bursts at 2.0 and 4.0 s, the stop past 4.5 s on the shared clock, and the
# removal on the first check after the last particle dies, about 9 s in.
func _check_stop_and_the_whole_life() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var smoke := _smoke()
	var draws := [0]
	smoke.random = func() -> float:
		draws[0] += 1
		return rng.randf()
	smoke.start(Vector2(10.0, 20.0), 0.0, 5, Vector2.ZERO)
	var clock := 100.0
	var spawned := clock
	var step := 1.0 / 60.0
	var bursts: Array[float] = []
	var removed_at := -1.0
	var alive_before := 0
	for _frame in range(60 * 12):
		# The player's gate runs before the effects list.
		if clock - spawned > 4.5 and smoke.stop():
			removed_at = clock - spawned
			break
		alive_before = smoke.alive
		smoke.tick(clock)
		if smoke.alive > alive_before:
			bursts.append(clock - spawned)
		clock += step
	_expect(bursts.size() == 2, "two bursts before the stop, got %s" % [bursts])
	if bursts.size() == 2:
		_expect(bursts[0] >= 2.0 and bursts[0] < 2.0 + 2.0 * step, "the first burst lands just past 2.0 s, at %f" % bursts[0])
		_expect(bursts[1] > 3.9 and bursts[1] < 4.1, "the second about 2.0 s later, at %f" % bursts[1])
	_expect(draws[0] == 100 * 8, "a smoke emits 100 particles in all, got %d" % (draws[0] / 8))
	_expect(smoke.stopped, "the gate stops the emission for good")
	# The second burst's particles are pre-aged 0 to 0.6 s and live out the rest of 5.0.
	var last_burst: float = bursts[bursts.size() - 1] if not bursts.is_empty() else 4.0
	_expect(
		removed_at > last_burst + 4.4 and removed_at <= last_burst + 5.0 + 2.0 * step,
		"the smoke goes on the first check after its last particle dies, at %f" % removed_at
	)
	_drop(smoke)
