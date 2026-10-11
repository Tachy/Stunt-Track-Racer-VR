class_name TyreSquealSynth
extends Node3D
## Tyre squeal as friction-induced vibration, one oscillator per wheel (the
## physics of a bowed string or a squealing brake): the tread / carcass
## mode of the tyre - a mass on a spring with a little damping - rides on
## the road, which runs underneath it at the wheel's sliding speed. Friction
## couples the two, Karnopp style: the mode sticks to the road until its
## spring pulls harder than static friction allows, then slips with sliding
## friction that falls off with the relative speed (Stribeck). Static above
## sliding friction and that falling curve feed energy into the mode: it
## swings up by itself - squealing, rasping or breaking off, however load
## and sliding speed change. The friction scales with the load on the wheel;
## the road's texture makes the sliding speed under the tyre waver (and
## seeds the swing). The radiated sound is the mode's velocity against the
## road, relative to the sliding speed. Four slightly differently tuned tyres beat against each other.
## Optionally positional (opponent): then it reaches the listener through
## SoundPropagation (travel time, exact Doppler).

const RATE := 22050.0
## Tyre modes (Hz) per wheel: front left, front right, rear left, rear right
## (the wider rear tyres a little lower).
const MODE_HZ := [1180.0, 1225.0, 1010.0, 1045.0]
const DAMPING := 0.012           # damping ratio of the mode
const MU_STATIC := 1.25
const MU_SLIDE := 0.95           # sliding friction at high relative speed
const STRIBECK_V := 4.0          # m/s over which friction falls to MU_SLIDE
## Friction pull per load (acceleration of the mode per unit of mu at the
## static wheel load): sets how far the mode is pulled before it lets go.
const PULL := 22000.0
const STATIC_LOAD := 2200.0      # N on a wheel at rest
const TEXTURE := 0.02            # waver of the sliding speed from the road's texture
const TEXTURE_HZ := 180.0        # how fast it wavers (texture under the slide)
const SLIDE_MIN := 0.25          # m/s below which a wheel grips silently
## The sliding speed under the tyre follows the wheel's with this time
## constant (s): a sudden drop (a frame of the physics) would leave the mode
## swinging at the old speed - a burst far louder than the squeal, clipped.
const SLIDE_LAG := 0.04

## Per wheel: sliding speed (m/s) and load (N).
var slide := PackedFloat32Array([0, 0, 0, 0])
var load := PackedFloat32Array([0, 0, 0, 0])
var muted := false

var _player: Node
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []
var _propagation: SoundPropagation


func _init() -> void:
	for w in 4:
		_voices.append({"x": 0.0, "xd": 0.0, "stuck": true, "v": 0.0, "k": 0.0, "g": 0.0, "tex": 0.0, "hp": 0.0, "vs": 0.0})


func setup(positional: bool, volume_db := 0.0) -> TyreSquealSynth:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = gen
		p3.volume_db = volume_db
		p3.unit_size = 10.0
		p3.max_distance = 300.0
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
		var cam := get_viewport().get_camera_3d()
		out = _propagation.process(out, global_position, cam.global_position if cam else global_position)
	for x in out:
		_playback.push_frame(Vector2(x, x))


## Friction coefficient at relative sliding speed v (m/s): Stribeck - from
## MU_STATIC at rest falling to MU_SLIDE.
static func mu(v: float) -> float:
	return MU_SLIDE + (MU_STATIC - MU_SLIDE) * exp(-absf(v) / STRIBECK_V)


## The next `frames` samples for the current wheels (also used to render a
## demo offline).
func generate(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var dt := 1.0 / RATE
	var tex_a := minf(TAU * TEXTURE_HZ * dt, 1.0)
	var lag_a := 1.0 - exp(-dt / SLIDE_LAG)
	for w in 4:
		var vc: Dictionary = _voices[w]
		var sl := 0.0 if muted else slide[w]
		var ld := 0.0 if muted else load[w]
		var v1 := sl
		var k1 := PULL * clampf(ld / STATIC_LOAD, 0.0, 2.0)
		# heard only while it slides on the road
		var g1 := smoothstep(SLIDE_MIN, SLIDE_MIN * 3.0, sl) * (1.0 if ld > 0.0 else 0.0)
		var v0: float = vc["v"]
		var k0: float = vc["k"]
		var g0: float = vc["g"]
		vc["v"] = v1
		vc["k"] = k1
		vc["g"] = g1
		if g0 < 1e-4 and g1 < 1e-4:
			vc["x"] = 0.0
			vc["xd"] = 0.0
			vc["stuck"] = true
			vc["vs"] = v1
			continue
		var om := TAU * float(MODE_HZ[w])
		var om2 := om * om
		var damp := 2.0 * DAMPING * om
		var x: float = vc["x"]
		var xd: float = vc["xd"]
		var stuck: bool = vc["stuck"]
		var tex: float = vc["tex"]
		var hp: float = vc["hp"]
		var vs: float = vc["vs"]
		for i in frames:
			var t := float(i) / frames
			vs += (lerpf(v0, v1, t) - vs) * lag_a
			tex += (randf() * 2.0 - 1.0 - tex) * tex_a
			var vb := vs * (1.0 + TEXTURE * tex * 8.0)   # road speed under the mode
			var k := lerpf(k0, k1, t)
			var a_sd := -om2 * x - damp * xd     # spring and damper
			if stuck:
				# held by static friction while it can take the pull
				if absf(a_sd) <= k * MU_STATIC:
					xd = vb
					x += xd * dt
				else:
					stuck = false
			if not stuck:
				var vr := vb - xd                # road against the mode
				var a := a_sd + k * mu(vr) * signf(vr)
				var xd_new := xd + a * dt
				# caught again where the relative speed passes zero
				if signf(vb - xd_new) != signf(vr) and vr != 0.0:
					xd_new = vb
					stuck = true
				xd = xd_new
				x += xd * dt
			# radiated: the mode's velocity against the road's (no DC)
			var y := (xd - vb) / (vs + 1.0)
			hp += (y - hp) * 0.02
			out[i] += (y - hp) * lerpf(g0, g1, t) * 0.12
		vc["x"] = x
		vc["xd"] = xd
		vc["stuck"] = stuck
		vc["tex"] = tex
		vc["hp"] = hp
		vc["vs"] = vs
	return out
