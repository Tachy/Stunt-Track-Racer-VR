class_name SoundPropagation
extends RefCounted
## Sound travelling through air at 343 m/s from a moving source to a moving
## listener, as a variable delay line: what is heard at time t was emitted
## at t_e with c * (t - t_e) = |listener(t) - source(t_e)|. That one rule
## gives the travel time (a car 100 m away is heard 0.29 s late) and the
## exact Doppler shift for a moving source AND a moving listener -
## f' = f (c + v_listener) / (c - v_source), components along the line -
## without any pitch formula. The source path is kept as a short history
## so the emission point is the true retarded position.
##
## Feed it the synthesised (emitted) samples block by block; it returns the
## samples as heard at the listener. Loudness and direction stay with the
## AudioStreamPlayer3D (1/r, panning); its own Doppler stays off.

const SPEED_OF_SOUND := 343.0   # m/s, air at 20 degC
## Longest delay kept (s): 2 s = 686 m, beyond any player's max_distance.
const MAX_DELAY := 2.0

var rate: float
var _ring := PackedFloat32Array()
var _written := 0              # samples written in total (the audio clock)
var _hist_t: Array[float] = [] # source path: audio-clock time (s) ...
var _hist_p := PackedVector3Array()   # ... and position
var _delay := -1.0             # delay at the end of the last block (s)


func _init(sample_rate: float) -> void:
	rate = sample_rate
	_ring.resize(int(sample_rate * (MAX_DELAY + 0.5)))


## The current delay (s), for display / tests.
func delay() -> float:
	return maxf(_delay, 0.0)


## block: emitted samples; source/listener: positions now. Returns the
## block as heard at the listener.
func process(block: PackedFloat32Array, source: Vector3, listener: Vector3) -> PackedFloat32Array:
	var n := block.size()
	var size := _ring.size()
	for i in n:
		_ring[(_written + i) % size] = block[i]
	_written += n
	var t := _written / rate
	_record(t, source)
	var d := _retarded_delay(t, listener)
	var d0 := d if _delay < 0.0 else _delay
	var out := PackedFloat32Array()
	out.resize(n)
	var oldest := float(_written - size + 1)
	for i in n:
		# the delay changes smoothly across the block: that change IS the Doppler shift
		var k := float(_written - n + i)
		var pos := k - lerpf(d0, d, float(i + 1) / n) * rate
		if pos < 0.0 or pos < oldest:
			continue   # not emitted yet / too long ago
		var i0 := int(pos)
		var fr := pos - i0
		var a := _ring[i0 % size]
		var b := _ring[mini(i0 + 1, _written - 1) % size]
		out[i] = a + (b - a) * fr
	_delay = d
	return out


func _record(t: float, p: Vector3) -> void:
	_hist_t.append(t)
	_hist_p.append(p)
	# keep MAX_DELAY seconds of path
	var drop := 0
	while drop < _hist_t.size() - 2 and _hist_t[drop + 1] < t - MAX_DELAY - 0.2:
		drop += 1
	if drop > 0:
		_hist_t = _hist_t.slice(drop)
		_hist_p = _hist_p.slice(drop)


## Source position at time te (linear between the recorded points).
func _source_at(te: float) -> Vector3:
	var i := _hist_t.size() - 1
	while i > 0 and _hist_t[i - 1] > te:
		i -= 1
	if i == 0:
		return _hist_p[0]
	if _hist_t[i] <= te:
		return _hist_p[i]
	var t0 := _hist_t[i - 1]
	var u := (te - t0) / maxf(_hist_t[i] - t0, 1e-9)
	return _hist_p[i - 1].lerp(_hist_p[i], u)


## Solves c * d = |listener(t) - source(t - d)| by fixed-point iteration
## (converges since the source is far slower than sound).
func _retarded_delay(t: float, listener: Vector3) -> float:
	var d := listener.distance_to(_hist_p[_hist_p.size() - 1]) / SPEED_OF_SOUND
	for it in 6:
		d = listener.distance_to(_source_at(t - d)) / SPEED_OF_SOUND
	return minf(d, MAX_DELAY)
