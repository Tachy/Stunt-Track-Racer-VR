class_name TitleMusic
extends RefCounted
## 8-bit title music, synthesised like an NES (no audio files): pulse wave
## melody, pulse wave 16th arpeggio ostinato, 4-bit triangle bass, LFSR
## noise drums. D minor, 132 BPM, loops after 34 bars (~62 s).
##
## The harmony takes its cue from Karl Jenkins (Palladio, Adiemus): a
## driving ostinato under plain triads that move to distant chords over a
## common tone - F -> Ab (C stays), F -> Db (F stays), Bb minor as borrowed
## colour - then a deceptive C7 -> E minor that lifts the theme a whole tone,
## and a chromatic slide B -> Bb -> A back home to D minor.

const RATE := 22050
const BPM := 132.0
## Bump when the music changes: the cached render is keyed on it.
const VERSION := 1

# [chord, melody "note:eighths ...", drums, bass]
const INTRO := [
	["Dm", "", "none", "half"], ["Dm", "", "none", "half"],
	["Bb", "", "none", "half"], ["Bb", "", "none", "half"],
	["Gm", "", "light", "eighth"], ["Gm", "", "light", "eighth"],
	["Asus", "", "light", "eighth"], ["A", "", "roll", "eighth"],
]
const THEME := [
	["Dm", "A4:3 D5:3 E5:2", "full", "eighth"],
	["Bb", "F5:4 E5:2 D5:2", "full", "eighth"],
	["F", "C5:3 F5:3 G5:2", "full", "eighth"],
	["C", "A5:4 G5:2 E5:2", "full", "eighth"],
	["Dm", "A4:3 D5:3 E5:2", "full", "eighth"],
	["Bb", "F5:3 G5:3 A5:2", "full", "eighth"],
	["Gm", "Bb5:4 A5:2 G5:2", "full", "eighth"],
	["A", "A5:4 E5:2 C#5:2", "full", "eighth"],
]
const LIFT := [
	["F", "C6:4 A5:2 F5:2", "drive", "eighth"],
	["Ab", "C6:3 Ab5:3 Eb5:2", "drive", "eighth"],
	["Eb", "Bb5:4 G5:2 Eb5:2", "drive", "eighth"],
	["Bb", "F5:4 D5:2 F5:2", "drive", "eighth"],
	["F", "A5:3 C6:3 A5:2", "drive", "eighth"],
	["Db", "Ab5:4 F5:2 Db5:2", "drive", "eighth"],
	["Bbm", "F5:3 Db5:3 Bb4:2", "drive", "eighth"],
	["C7", "C5:2 E5:2 G5:2 Bb5:2", "roll", "eighth"],
]
const TURN := [
	["Bb", "F5:4 D5:2 Bb4:2", "full", "eighth"],
	["A7", "A4:2 C#5:2 E5:2 G5:2", "roll", "eighth"],
]
## 16th arpeggio over the chord tones [root, 3rd, 5th, octave, 3rd up].
const ARP := [0, 2, 3, 2, 1, 2, 3, 2, 0, 2, 3, 2, 4, 3, 2, 1]

const VOL_MELODY := 0.20
const VOL_ARP := 0.085
const VOL_BASS := 0.30
const VOL_KICK := 0.38
const VOL_SNARE := 0.15
const VOL_HAT := 0.06


## All bars in order: {chord, melody, drums, bass, shift (semitones)}.
static func song() -> Array:
	var out := []
	for part in [[INTRO, 0], [THEME, 0], [LIFT, 0], [THEME, 2], [TURN, 0]]:
		for b in part[0]:
			out.append({"chord": b[0], "melody": b[1], "drums": b[2], "bass": b[3], "shift": part[1]})
	return out


static func bar_samples() -> int:
	return roundi(RATE * 240.0 / BPM)


## MIDI note number of "A4", "C#5", "Bb4" (C4 = 60).
static func midi(n: String) -> int:
	var pc: int = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[n[0]]
	var i := 1
	if n[i] == "#":
		pc += 1
		i += 1
	elif n[i] == "b":
		pc -= 1
		i += 1
	return pc + 12 * (int(n.substr(i)) + 1)


## [root pitch class, intervals] of "Dm", "Bb", "C7", "Asus", "Bbm".
static func chord(c: String) -> Array:
	var i := 1
	var pc := midi(c[0] + "4") % 12
	if c.length() > 1 and (c[1] == "#" or c[1] == "b"):
		pc = (pc + (1 if c[1] == "#" else -1) + 12) % 12
		i = 2
	var iv: Array = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "sus": [0, 5, 7]}[c.substr(i)]
	return [pc, iv]


static func freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


## The whole loop (or bars [from, to)) as samples, -1..1.
static func render(from := 0, to := -1) -> PackedFloat32Array:
	var bars := song()
	if to < 0:
		to = bars.size()
	var bs := bar_samples()
	var buf := PackedFloat32Array()
	buf.resize((to - from) * bs)
	var s16 := bs / 16
	for k in range(from, to):
		var b: Dictionary = bars[k]
		var at := (k - from) * bs
		var sh: int = b["shift"]
		var ch := chord(b["chord"])
		var pc: int = (int(ch[0]) + sh) % 12
		var iv: Array = ch[1]
		# arpeggio, root between A3 and G#4
		var r := 57 + posmod(pc - 9, 12)
		var tones := [r + iv[0], r + iv[1], r + iv[2], r + 12, r + 12 + iv[1]]
		if iv.size() > 3:
			tones[3] = r + iv[3]   # dominant 7th in place of the octave
		for j in 16:
			_pulse(buf, at + j * s16, int(s16 * 0.85), freq(tones[ARP[j]]), 0.125, VOL_ARP, false)
		# bass: triangle, root in octave 2, octave jumps on the off-beats
		var root := 36 + pc
		if b["bass"] == "half":
			for j in 2:
				_triangle(buf, at + j * bs / 2, int(bs / 2 * 0.95), freq(root), VOL_BASS)
		else:
			for j in 8:
				_triangle(buf, at + j * bs / 8, int(bs / 8 * 0.8), freq(root + (12 if j % 2 == 1 else 0)), VOL_BASS)
		# melody
		var pos := 0
		for tok in String(b["melody"]).split(" ", false):
			var p := tok.split(":")
			var n := int(p[1]) * bs / 8
			if p[0] != "-":
				_pulse(buf, at + pos, n - int(0.012 * RATE), freq(midi(p[0]) + sh), 0.25, VOL_MELODY, true)
			pos += n
		_drums(buf, at, bs, b["drums"])
	return _normalised(buf)


static func _drums(buf: PackedFloat32Array, at: int, bs: int, style: String) -> void:
	var e := bs / 8
	match style:
		"light":
			_kick(buf, at)
			for j in 8:
				_noise(buf, at + j * e, 0.05, 60.0, 1, VOL_HAT)
		"full", "drive":
			for j in [0, 3, 4]:
				_kick(buf, at + j * e)
			for j in [2, 6]:
				_snare(buf, at + j * e, VOL_SNARE)
			var hats := 16 if style == "drive" else 8
			for j in hats:
				_noise(buf, at + j * bs / hats, 0.04, 70.0, 1, VOL_HAT * (1.0 if j % 2 == 0 else 0.6))
		"roll":
			_kick(buf, at)
			_snare(buf, at + 2 * e, VOL_SNARE)
			for j in range(8, 16):
				_snare(buf, at + j * bs / 16, VOL_SNARE * (0.45 + 0.08 * (j - 8)))


# --- voices --------------------------------------------------------------------------

static func _add(buf: PackedFloat32Array, idx: int, v: float) -> void:
	var n := buf.size()
	buf[idx % n] += v   # tails wrap around: seamless loop


static func _pulse(buf: PackedFloat32Array, start: int, n: int, f: float, duty: float, vol: float, vibrato: bool) -> void:
	var ph := 0.0
	var rel := 0.015 * RATE
	for i in n:
		var t := float(i) / RATE
		var fi := f
		if vibrato and t > 0.22:
			fi *= 1.0 + 0.005 * sin(TAU * 5.5 * t)
		ph = fmod(ph + fi / RATE, 1.0)
		var env := minf(1.0, t / 0.004) * (0.6 + 0.4 * exp(-t * 10.0)) * minf(1.0, (n - i) / rel)
		_add(buf, start + i, (vol if ph < duty else -vol) * env)


## NES triangle: 16 steps, no volume control (so just on/off with a click guard).
static func _triangle(buf: PackedFloat32Array, start: int, n: int, f: float, vol: float) -> void:
	var ph := 0.0
	for i in n:
		ph = fmod(ph + f / RATE, 1.0)
		var v := 1.0 - 4.0 * absf(ph - 0.5)
		v = floorf(v * 7.5 + 7.5) / 7.5 - 1.0
		var env := minf(1.0, i / 40.0) * minf(1.0, (n - i) / 80.0)
		_add(buf, start + i, v * vol * env)


static func _kick(buf: PackedFloat32Array, start: int) -> void:
	var n := int(0.16 * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph = fmod(ph + (45.0 + 120.0 * exp(-t * 30.0)) / RATE, 1.0)
		var v := 1.0 - 4.0 * absf(ph - 0.5)
		_add(buf, start + i, v * VOL_KICK * exp(-t * 16.0))


static func _snare(buf: PackedFloat32Array, start: int, vol: float) -> void:
	_noise(buf, start, 0.18, 20.0, 2, vol)
	var n := int(0.06 * RATE)
	var ph := 0.0
	for i in n:
		ph = fmod(ph + 190.0 / RATE, 1.0)
		_add(buf, start + i, (1.0 - 4.0 * absf(ph - 0.5)) * vol * 0.8 * exp(-float(i) / RATE * 40.0))


## 15-bit LFSR noise (the NES noise channel); period = samples per shift.
static func _noise(buf: PackedFloat32Array, start: int, dur: float, decay: float, period: int, vol: float) -> void:
	var reg := 1
	var n := int(dur * RATE)
	var v := 1.0
	for i in n:
		if i % period == 0:
			var fb := (reg ^ (reg >> 1)) & 1
			reg = (reg >> 1) | (fb << 14)
			v = 1.0 if reg & 1 else -1.0
		_add(buf, start + i, v * vol * exp(-float(i) / RATE * decay))


static func _normalised(buf: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for x in buf:
		peak = maxf(peak, absf(x))
	if peak > 0.95:
		var k := 0.95 / peak
		for i in buf.size():
			buf[i] *= k
	return buf


## 16-bit PCM of the loop, cached in user:// after the first render.
static func pcm() -> PackedByteArray:
	var path := "user://title_music_v%d.pcm" % VERSION
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() == song().size() * bar_samples() * 2:
		return bytes
	var samples := render()
	bytes = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(samples[i] * 32000.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
	return bytes


static func stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = bytes.size() / 2
	return w
