class_name EngineSynth
extends Node3D
## Procedural engine buzz (pulse wave + sub rumble) plus wind noise,
## reminiscent of the Amiga original. Optionally positional (opponent).

const RATE := 16000.0

var rpm := 0.0       # 0..1
var load := 0.0      # 0..1 throttle
var wind := 0.0      # 0..1
var boost := false
var muted := false

var _player: Node
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase_sub := 0.0
var _freq := 40.0
var _lp := 0.0
var _gain := 0.0


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
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = gen
		p2.volume_db = volume_db
		_player = p2
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
	var target_f := 38.0 + 165.0 * clampf(rpm, 0.0, 1.2) * (1.08 if boost else 1.0)
	var target_gain := 0.0 if muted else (0.35 + 0.65 * load)
	var f0 := _freq
	var g0 := _gain
	var w := clampf(wind, 0.0, 1.0) * (0.0 if muted else 1.0)
	for i in frames:
		var t := float(i) / frames
		var f := lerpf(f0, target_f, t)
		var g := lerpf(g0, target_gain, t)
		_phase += f / RATE
		if _phase >= 1.0:
			_phase -= 1.0
		_phase_sub += f * 0.5 / RATE
		if _phase_sub >= 1.0:
			_phase_sub -= 1.0
		var pulse := 1.0 if _phase < 0.32 else -1.0
		var sub := sin(TAU * _phase_sub)
		_lp += (randf() * 2.0 - 1.0 - _lp) * 0.08
		var sample := (pulse * 0.22 + sub * 0.28) * g + _lp * w * 0.9
		_playback.push_frame(Vector2(sample, sample))
	_freq = target_f
	_gain = target_gain
