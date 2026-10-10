class_name EngineSynth
extends Node3D
## Procedural engine buzz (pulse wave + sub rumble), reminiscent of the
## Amiga original (the wind is WindSynth's). `running` starts the engine (the
## starter turns it over, it catches with a flare of revs) or stops it (it
## runs down and dies). Optionally positional (opponent):
## then it reaches the listener through SoundPropagation (travel time,
## exact Doppler).

const RATE := 16000.0

var rpm := 0.0       # 0..1
var load := 0.0      # 0..1 throttle
var boost := false
var muted := false
var running := false

const CRANK_TIME := 0.7     # s the starter turns the engine over
const CRANK_HZ := 9.0       # compression strokes per second while cranking
const STARTER_HZ := 150.0   # whine of the starter motor
const RUN_DOWN := 0.5       # s time constant of the engine dying

var _was_running := false
var _crank := 0.0           # s of starter left
var _life := 0.0            # 0 dead .. 1 running
var _flare := 0.0           # rev flare when it catches
var _phase_starter := 0.0

var _player: Node
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase_sub := 0.0
var _freq := 40.0
var _gain := 0.0
var _propagation: SoundPropagation


func setup(positional: bool, volume_db := 0.0) -> EngineSynth:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = gen
		p3.volume_db = volume_db
		p3.unit_size = 12.0
		p3.max_distance = 400.0
		_player = p3
		_propagation = SoundPropagation.new(RATE)
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = gen
		p2.volume_db = volume_db
		_player = p2
	_player.bus = &"Vehicles"   # Sfx.VEHICLE_BUS (tunnel echo)
	add_child(_player)
	return self


func _ready() -> void:
	if _player == null:
		setup(false)
	_player.play()
	_playback = _player.get_stream_playback()


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var out := generate(frames)
	if _propagation:
		out = _propagation.process(out, global_position, _listener())
	for x in out:
		_playback.push_frame(Vector2(x, x))


func _listener() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else global_position


## The next `frames` samples as emitted at the car.
func generate(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var dt := frames / RATE
	if running and not _was_running:
		_crank = CRANK_TIME
	_was_running = running
	var cranking := running and _crank > 0.0
	if cranking:
		_crank -= dt
		if _crank <= 0.0:
			_life = 1.0
			_flare = 1.0      # it catches
	elif not running:
		_crank = 0.0
		_life *= exp(-dt / RUN_DOWN)
	_flare *= exp(-dt * 3.0)
	var revs := 38.0 + 165.0 * clampf(rpm, 0.0, 1.2) * (1.08 if boost else 1.0) + 60.0 * _flare
	# turned over by the starter: slow chugging; dying: the revs sink away
	var target_f := CRANK_HZ if cranking else revs * (0.2 + 0.8 * _life)
	var target_gain := 0.0 if muted else ((0.3 if cranking else (0.35 + 0.65 * load) * _life) + 0.25 * _flare)
	var starter := 0.0 if muted or not cranking else 0.09
	var f0 := _freq
	var g0 := _gain
	for i in frames:
		var t := float(i) / frames
		var f := lerpf(f0, target_f, t)
		var g := lerpf(g0, target_gain, t)
		_phase_starter = fmod(_phase_starter + STARTER_HZ / RATE, 1.0)
		_phase += f / RATE
		if _phase >= 1.0:
			_phase -= 1.0
		_phase_sub += f * 0.5 / RATE
		if _phase_sub >= 1.0:
			_phase_sub -= 1.0
		var pulse := 1.0 if _phase < 0.32 else -1.0
		var sub := sin(TAU * _phase_sub)
		out[i] = (pulse * 0.22 + sub * 0.28) * g + (_phase_starter * 2.0 - 1.0) * starter
	_freq = target_f
	_gain = target_gain
	return out
