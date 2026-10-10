class_name CraneMotorSynth
extends Node3D
## Procedural sound of the crane's two electric drives, the chain hoist and
## the trolley. Each motor's tone rises with its speed without any limit, as
## a Shepard-Risset glissando: a stack of octave-spaced partials that all
## glide upwards while a fixed bell over log frequency fades them in at the
## bottom and out at the top - the faster the axis runs, the further the
## tone climbs, endlessly. The gearbox whine is a second, quieter stack at
## the gear ratio (louder under load), plus a little brush / bearing hiss.
## Loudness follows how fast each axis moves (`hoist`, `trolley` in m/s);
## speeding up loads the motor. Positional: it sits on the trolley.

const RATE := 16000.0
## Partials per stack (octaves) and the lowest one's frequency at pitch 0.
const PARTIALS := 7
## Phase slots per stack: partial j (an absolute octave) keeps its phase in
## slot j mod SLOTS while it glides through the stack.
const SLOTS := 16

## Per drive, the mechanics: radius of the chain wheel / running wheel (m),
## gear ratio motor : wheel, pole pairs of the motor (its magnetic tone is
## turns/s x pole pairs), teeth of the motor pinion (the gear mesh tone is
## turns/s x teeth); lowest partial (Hz) of the stack, loudness.
const HOIST := {"radius": 0.12, "ratio": 40.0, "poles": 2.0, "teeth": 13.0, "low": 25.0, "level": 1.0}
const TROLLEY := {"radius": 0.15, "ratio": 25.0, "poles": 2.0, "teeth": 11.0, "low": 35.0, "level": 0.8}
## Axis speed (m/s) below which a drive fades out (it stands, brake on).
const RUN_SPEED := 0.05

var hoist := 0.0     # m/s the chain runs in or out
var trolley := 0.0   # m/s the trolley travels
var muted := false

var _player: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _voices: Array = []


func setup(volume_db := 0.0) -> CraneMotorSynth:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.1
	_player = AudioStreamPlayer3D.new()
	_player.stream = gen
	_player.volume_db = volume_db
	_player.unit_size = 8.0
	_player.max_distance = 300.0
	_player.bus = &"Vehicles"   # Sfx.VEHICLE_BUS (tunnel echo)
	add_child(_player)
	return self


func _init() -> void:
	for cfg in [HOIST, TROLLEY]:
		var ph := PackedFloat32Array()
		ph.resize(SLOTS * 2)    # motor stack, gear stack
		_voices.append({"cfg": cfg, "speed": 0.0, "gain": 0.0, "pitch": 0.0, "ph": ph, "hiss": 0.0, "load": 0.0})


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


## Motor turns per second at axis speed v (m/s): the wheel's turns times
## the gear ratio.
static func motor_turns(cfg: Dictionary, v: float) -> float:
	return v / (TAU * float(cfg["radius"])) * float(cfg["ratio"])


## Frequency (Hz) of a drive's magnetic tone at axis speed v: proportional
## to the speed, no limit.
static func tone_hz(cfg: Dictionary, v: float) -> float:
	return motor_turns(cfg, v) * float(cfg["poles"])


## Pitch in octaves of that tone: log2 of its frequency over the stack's
## lowest partial - grows without limit.
static func pitch_of(cfg: Dictionary, v: float) -> float:
	return log(tone_hz(cfg, maxf(v, RUN_SPEED)) / float(cfg["low"])) / log(2.0)


## Loudness of a partial u octaves above the stack's lowest frequency: a
## raised-cosine bell over the stack's span - the top one fades out while a
## new one fades in at the bottom.
static func bell(u: float) -> float:
	if u <= 0.0 or u >= PARTIALS:
		return 0.0
	return 0.5 - 0.5 * cos(TAU * u / PARTIALS)


## The next `frames` samples for the current axis speeds (also used to
## render a demo offline).
func generate(frames: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var dt := frames / RATE
	var speeds := [0.0 if muted else absf(hoist), 0.0 if muted else absf(trolley)]
	for vi in _voices.size():
		var v: Dictionary = _voices[vi]
		var cfg: Dictionary = v["cfg"]
		var speed: float = speeds[vi]
		# speeding up: the motor works harder for a moment
		var accel := absf(speed - float(v["speed"])) / maxf(dt, 1e-4)
		var load0: float = v["load"]
		var load1 := lerpf(load0, clampf(accel / 3.0, 0.0, 1.0), 0.3)
		var g0: float = v["gain"]
		var g1 := smoothstep(RUN_SPEED, RUN_SPEED * 6.0, speed) * float(cfg["level"]) * (1.0 + 0.4 * load1)
		var p0: float = v["pitch"]
		var p1 := pitch_of(cfg, speed) if speed > RUN_SPEED else p0
		v["speed"] = speed
		v["load"] = load1
		v["gain"] = g1
		v["pitch"] = p1
		if g0 < 0.0005 and g1 < 0.0005:
			continue
		var low: float = cfg["low"]
		# the gear mesh tone is teeth / pole pairs times the magnetic one
		var gear_p := log(float(cfg["teeth"]) / float(cfg["poles"])) / log(2.0)
		var ph: PackedFloat32Array = v["ph"]
		var hiss: float = v["hiss"]
		# the partials of both stacks across this block: partial j of a stack
		# at pitch p sits p - j octaves above its lowest frequency (glides
		# continuously, also when it wraps)
		var parts := []    # [slot, f0, f1, w0, w1, gear]
		for stack in 2:
			var q0 := p0 + (gear_p if stack == 1 else 0.0)
			var q1 := p1 + (gear_p if stack == 1 else 0.0)
			for jj in range(int(floor(minf(q0, q1))) - PARTIALS + 1, int(floor(maxf(q0, q1))) + 1):
				var w0 := bell(q0 - jj)
				var w1 := bell(q1 - jj)
				if w0 <= 0.0 and w1 <= 0.0:
					continue
				var f0 := low * pow(2.0, q0 - jj)
				var f1 := low * pow(2.0, q1 - jj)
				if minf(f0, f1) >= RATE * 0.45:
					continue
				parts.append([posmod(jj, SLOTS) + stack * SLOTS, f0, f1, w0, w1, stack == 1])
		for i in frames:
			var t := float(i) / frames
			var g := lerpf(g0, g1, t)
			var gear_w := 0.25 + 0.25 * lerpf(load0, load1, t)
			var s := 0.0
			for pt in parts:
				var k: int = pt[0]
				ph[k] = fmod(ph[k] + lerpf(pt[1], pt[2], t) / RATE, 1.0)
				s += sin(TAU * ph[k]) * lerpf(pt[3], pt[4], t) * (gear_w if pt[5] else 1.0)
			var noise := randf() * 2.0 - 1.0
			hiss += (noise - hiss) * 0.35
			out[i] += (s * 0.22 + (noise - hiss) * 0.05) * g * 0.3
		v["ph"] = ph
		v["hiss"] = hiss
	return out
