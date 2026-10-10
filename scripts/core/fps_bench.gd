class_name FpsBench
extends Node
## Debug load test (--fps-bench): VSync off and no frame cap, then the frame
## rate the game reaches - noted each second (average, slowest frame, CPU
## time of process and physics, GPU time of the window) and printed with a
## summary when the game quits (printing while it runs would itself cost
## frames: a console write takes milliseconds).

var _t := 0.0
var _frames := 0
var _worst := 0.0
var _all: PackedFloat32Array = []   # frame times (ms) after the warm-up
var _gpu := 0.0
var _elapsed := 0.0
var _log := PackedStringArray()
const WARMUP := 3.0                  # s not counted (loading, shader compiles)


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("[FPSBench] VSync off, no frame cap, window %s" % [DisplayServer.window_get_size()])


func _process(delta: float) -> void:
	# (XrManager switches VSync on for the desktop after startup: keep it off)
	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_elapsed += delta
	var ms := delta * 1000.0
	if _elapsed > WARMUP:
		_all.append(ms)
	_frames += 1
	_worst = maxf(_worst, ms)
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	_t += delta
	if _t >= 1.0:
		_log.append("[FPSBench] %d FPS, slowest frame %.1f ms, CPU process %.2f ms physics %.2f ms, GPU %.2f ms" % [_frames / _t, _worst,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _gpu / maxf(_frames, 1)])
		_t = 0.0
		_frames = 0
		_worst = 0.0
		_gpu = 0.0


func _exit_tree() -> void:
	for line in _log:
		print(line)
	if _all.is_empty():
		return
	var sorted := _all.duplicate()
	sorted.sort()
	var total := 0.0
	for x in sorted:
		total += x
	var avg := total / sorted.size()
	var low1 := sorted[int(sorted.size() * 0.99)]
	print("[FPSBench] summary: %d frames, average %.0f FPS (%.2f ms), 1%% low %.0f FPS (%.2f ms), slowest %.1f ms" % [sorted.size(), 1000.0 / avg, avg, 1000.0 / low1, low1, sorted[sorted.size() - 1]])
