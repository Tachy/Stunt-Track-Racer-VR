class_name DirtSynth
extends Node3D
## Procedural sound of knobbly tyres sliding on dirt (no rubber squeal):
## band-passed noise for the scrub, a low earthy rumble, random grit
## crackles (stones, clods) and a flutter at the rate the tread knobs pass.
## All of it grows with `slide` (0..1). Optionally positional (opponent):
## then it reaches the listener through SoundPropagation (travel time,
## exact Doppler).

const RATE := 16000.0
## Tread knob spacing on the tyre (m): flutter rate = speed / spacing.
const KNOB_SPACING := 0.09

var slide := 0.0     # 0..1 how hard the tyres slide
var speed := 0.0     # m/s over the ground
var muted := false

var _player: Node
var _playback: AudioStreamGeneratorPlayback
var _gain := 0.0
var _center := 500.0
# state-variable band-pass, rumble low-pass, grit burst, flutter phase
var _bp_low := 0.0
var _bp_band := 0.0
var _rumble := 0.0
var _grit := 0.0
var _grit_env := 0.0
var _flutter := 0.0
var _propagation: SoundPropagation


func setup(positional: bool, volume_db := 0.0) -> DirtSynth:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = gen
		p3.volume_db = volume_db
		p3.unit_size = 10.0
		p3.max_distance = 250.0
		_player = p3
		_propagation = SoundPropagation.new(RATE)
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
	var out := generate(frames)
	if _propagation:
		var cam := get_viewport().get_camera_3d()
		out = _propagation.process(out, global_position, cam.global_position if cam else global_position)
	for x in out:
		_playback.push_frame(Vector2(x, x))


## The next `frames` samples for the current slide / speed (also used to
## render a demo offline).
func generate(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var s := 0.0 if muted else clampf(slide, 0.0, 1.0)
	# loudness rises fast at first (a light drift is clearly audible)
	var target_gain := pow(s, 0.6)
	# harder slide: brighter scrub, more grit
	var target_center := 380.0 + 900.0 * s
	var grit_rate := (25.0 + 260.0 * s) / RATE      # crackles per sample
	var flutter_hz := clampf(speed / KNOB_SPACING, 0.0, 140.0)
	var g0 := _gain
	var c0 := _center
	for i in frames:
		var t := float(i) / frames
		var g := lerpf(g0, target_gain, t)
		if g < 0.001:
			continue
		var noise := randf() * 2.0 - 1.0
		# band-pass (Chamberlin SVF, q ~ 1.4)
		var f := 2.0 * sin(PI * lerpf(c0, target_center, t) / RATE)
		_bp_low += f * _bp_band
		var high := noise - _bp_low - 0.7 * _bp_band
		_bp_band += f * high
		# earthy rumble: heavily low-passed noise
		_rumble += (noise - _rumble) * 0.025
		# grit: short random bursts of raw noise
		if randf() < grit_rate:
			_grit_env = 0.4 + randf() * 0.6
		_grit_env *= 0.965
		_grit = noise * _grit_env
		# knobs slapping the ground
		_flutter = fmod(_flutter + flutter_hz / RATE, 1.0)
		var knob := 0.75 + 0.25 * signf(sin(TAU * _flutter))
		out[i] = (_bp_band * 0.55 + _rumble * 1.6) * knob * g + _grit * 0.22 * g
	_gain = target_gain
	_center = target_center
	return out
