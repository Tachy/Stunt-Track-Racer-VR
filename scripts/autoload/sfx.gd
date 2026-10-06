extends Node
## One-shot sound effects, synthesised at startup (no audio files needed).

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["thump"] = _wav(_thump(0.35, 55.0))
	_streams["bump"] = _wav(_thump(0.15, 90.0))
	_streams["crash"] = _wav(_noise_burst(0.7, 0.03))
	_streams["scrape"] = _wav(_noise_burst(0.25, 0.25))
	_streams["clank"] = _wav(_clank())
	_streams["beep"] = _wav(_tone(0.12, 880.0))
	_streams["beep_low"] = _wav(_tone(0.18, 440.0))
	_streams["drop"] = _wav(_sweep(0.5, 600.0, 200.0))
	_streams["wreck"] = _wav(_sweep(1.2, 300.0, 40.0))


func play(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sfx_name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _thump(dur: float, freq: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 14.0)
		var f := freq * (1.0 - 0.5 * t / dur)
		ph += f / RATE
		out.append((sin(TAU * ph) * 0.9 + (randf() * 2.0 - 1.0) * 0.25 * exp(-t * 40.0)) * env)
	return out


static func _noise_burst(dur: float, smooth: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(dur * RATE)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (randf() * 2.0 - 1.0 - lp) * (1.0 - smooth)
		out.append(lp * exp(-t * 5.0) * 0.9)
	return out


static func _clank() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(0.45 * RATE)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in 3:
			var start := k * 0.11
			if t >= start:
				var tt := t - start
				s += (sin(TAU * 1250.0 * tt) * 0.5 + sin(TAU * 1870.0 * tt) * 0.3) * exp(-tt * 30.0)
		out.append(s * 0.6)
	return out


static func _tone(dur: float, freq: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(dur * RATE)
	for i in n:
		var t := float(i) / RATE
		out.append((1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0) * 0.3 * minf(1.0, (dur - t) * 40.0))
	return out


static func _sweep(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += lerpf(f0, f1, t / dur) / RATE
		out.append((1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * 0.25 * (1.0 - t / dur))
	return out
