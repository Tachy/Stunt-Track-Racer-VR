class_name WindSynth
extends Node3D
## Wind noise of the car moving through still air, as aeroacoustics has it:
## flow noise from surfaces and edges is dipole sound, its power grows with
## the sixth power of the speed (amplitude ~ v^3: +18 dB per doubling),
## and its frequencies scale with the speed (Strouhal number St ~ 0.2:
## f = St v / d). Three parts:
## - the hiss of the turbulent boundary layer around the open cockpit
##   (broadband, centre frequency rising with v),
## - the Aeolian tones of the roll cage tubes (vortex shedding, narrow
##   bands at St v / d for the tube diameters),
## - the buffeting of the cockpit opening (low rumble), whose slow gusts
##   also swell the hiss.
## Only the absolute speed counts (`speed`, m/s through the air), however
## the car moves - driving, flying, falling, on the crane.

const RATE := 22050.0
const STROUHAL := 0.2
## Roll cage tube diameters (m): their Aeolian tones.
const TUBES := [0.032, 0.045]
## Size of the cockpit opening (m): buffeting and gusts.
const OPENING := 0.9
## Speed (m/s) at which the noise has the loudness 1 (amplitude ~ v^3).
const V_REF := 60.0

var speed := 0.0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _gain := 0.0
var _v := 0.0
# state-variable filters: hiss, tubes, rumble; gust low-pass
var _hiss := [0.0, 0.0]
var _tubes := [[0.0, 0.0], [0.0, 0.0]]
var _rumble := 0.0
var _gust := 0.0


func setup(volume_db := 0.0) -> WindSynth:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = volume_db
	_player.bus = &"Vehicles"   # Sfx.VEHICLE_BUS (tunnel echo)
	add_child(_player)
	return self


func _ready() -> void:
	if _player == null:
		setup()
	_player.play()
	_playback = _player.get_stream_playback()


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	for x in generate(frames):
		_playback.push_frame(Vector2(x, x))


## Loudness (amplitude) at speed v: dipole flow noise, power ~ v^6.
static func level(v: float) -> float:
	return pow(maxf(v, 0.0) / V_REF, 3.0)


## Vortex shedding frequency (Hz) behind a body of size d at speed v.
static func shedding_hz(v: float, d: float) -> float:
	return STROUHAL * v / d


## One step of a state-variable band-pass (Chamberlin) on x; st = [low,
## band]; returns the band output.
static func _band(st: Array, x: float, f_hz: float, damp: float) -> float:
	var f := 2.0 * sin(PI * minf(f_hz, RATE * 0.2) / RATE)
	st[0] += f * st[1]
	var high: float = x - st[0] - damp * st[1]
	st[1] += f * high
	return st[1]


## The next `frames` samples for the current speed (also used to render a
## demo offline).
func generate(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var v1 := maxf(speed, 0.0)
	var g1 := level(v1)
	var v0 := _v
	var g0 := _gain
	_v = v1
	_gain = g1
	if g0 < 1e-5 and g1 < 1e-5:
		return out
	for i in frames:
		var t := float(i) / frames
		var v := lerpf(v0, v1, t)
		var g := lerpf(g0, g1, t)
		var noise := randf() * 2.0 - 1.0
		# gusts: the opening's buffeting, a few Hz, swells everything a bit
		var fb := shedding_hz(v, OPENING)
		_gust += (randf() * 2.0 - 1.0 - _gust) * minf(TAU * fb * 2.0 / RATE, 1.0)
		var swell := 1.0 + 3.0 * _gust
		# (a band of white noise gets louder the wider it is, and the bands
		# widen with their frequency: each is scaled back by sqrt(f), so the
		# whole spectrum just slides up and the power stays ~ v^6)
		# boundary layer hiss: broadband, its centre rising with the speed
		var fh := clampf(45.0 * v, 150.0, 4000.0)
		var hiss := _band(_hiss, noise, fh, 1.4) * sqrt(1000.0 / fh)
		# Aeolian tones of the tubes: narrow bands
		var tone := 0.0
		for k in TUBES.size():
			var ft := shedding_hz(v, TUBES[k])
			tone += _band(_tubes[k], noise, ft, 0.12) * sqrt(200.0 / maxf(ft, 1.0))
		# rumble: low-passed noise around the buffeting
		var fr := maxf(fb * 6.0, 20.0)
		_rumble += (noise - _rumble) * minf(TAU * fr / RATE, 1.0)
		out[i] = (hiss * 0.5 + tone * 0.05 + _rumble * sqrt(60.0 / fr) * 0.6) * swell * g * 0.4
	return out
