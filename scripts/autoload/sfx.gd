extends Node
## One-shot sound effects, synthesised at startup (no audio files needed),
## and the menu's title music (TitleMusic, rendered in a thread once and
## then cached in user://). Vehicle sounds (engines, sliding tyres, crashes)
## run through the "Vehicles" bus, whose reverb is the tunnel echo.

const RATE := 22050
const MUSIC_DB := -7.0
const VEHICLE_BUS := "Vehicles"
## Sounds of the cars (others, like the lap beep, stay dry).
const VEHICLE_SOUNDS := ["thump", "bump", "crash", "scrape", "wreck"]
## Reverb wet level at full tunnel echo.
const TUNNEL_WET := 0.5

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var music: AudioStreamWAV
var _music_player: AudioStreamPlayer
var _music_thread: Thread
var _music_wanted := false
var _music_fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_vehicle_bus()
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
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	if DisplayServer.get_name() != "headless":
		_music_thread = Thread.new()
		_music_thread.start(_render_music)


func _exit_tree() -> void:
	if _music_thread:
		_music_thread.wait_to_finish()


# --- tunnel echo ---------------------------------------------------------------------

## A bus for the vehicle sounds with a reverb tuned like a long concrete
## tube: big room, little damping (hard walls), a short pre-delay for the
## ~11 m between the walls. Off (bypassed) outside tunnels.
func _make_vehicle_bus() -> void:
	if AudioServer.get_bus_index(VEHICLE_BUS) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, VEHICLE_BUS)
	AudioServer.set_bus_send(idx, "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.85
	rev.damping = 0.15
	rev.spread = 0.9
	rev.hipass = 0.08
	rev.predelay_msec = 35.0
	rev.predelay_feedback = 0.35
	rev.dry = 1.0
	rev.wet = 0.0
	AudioServer.add_bus_effect(idx, rev)
	AudioServer.set_bus_effect_enabled(idx, 0, false)


## Tunnel echo amount 0 (open air) .. 1 (inside a tunnel).
func set_tunnel_echo(amount: float) -> void:
	var idx := AudioServer.get_bus_index(VEHICLE_BUS)
	if idx < 0:
		return
	var rev := AudioServer.get_bus_effect(idx, 0) as AudioEffectReverb
	rev.wet = TUNNEL_WET * clampf(amount, 0.0, 1.0)
	AudioServer.set_bus_effect_enabled(idx, 0, amount > 0.001)


# --- title music -------------------------------------------------------------------

func _render_music() -> void:
	_music_rendered.call_deferred(TitleMusic.pcm())


func _music_rendered(bytes: PackedByteArray) -> void:
	_music_thread.wait_to_finish()
	_music_thread = null
	music = TitleMusic.stream(bytes)
	print("[Sfx] title music ready (%.0f s loop)" % (bytes.size() / 2.0 / TitleMusic.RATE))
	if _music_wanted:
		play_music()


## Starts the title music (as soon as it is rendered), unless switched off.
func play_music() -> void:
	_music_wanted = true
	if music == null or not Settings.music or (_music_player.playing and _music_fade == null):
		return
	if _music_fade:
		_music_fade.kill()
		_music_fade = null
	if not _music_player.playing:
		_music_player.stream = music
		_music_player.play()
	_music_player.volume_db = MUSIC_DB


## Fades the title music out.
func stop_music(fade := 0.8) -> void:
	_music_wanted = false
	if not _music_player.playing or _music_fade:
		return
	_music_fade = create_tween()
	_music_fade.tween_property(_music_player, "volume_db", -50.0, fade)
	_music_fade.tween_callback(func():
		_music_player.stop()
		_music_fade = null)


func play(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sfx_name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sfx_name]
	p.bus = VEHICLE_BUS if sfx_name in VEHICLE_SOUNDS else "Master"
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
