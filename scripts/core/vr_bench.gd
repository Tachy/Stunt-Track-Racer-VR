class_name VrBench
extends Node
## Debug benchmark (--vr-bench): renders two off-screen eye views at the
## Pimax per-eye resolution from the cockpit and logs the measured GPU time,
## to estimate VR performance without a headset.

const EYE_SIZES := [Vector2i(5692, 4220), Vector2i(5194, 4220)]
const IPD := 0.064

var _vps: Array[SubViewport] = []
var _cams: Array[Camera3D] = []
var _t := 0.0
var _acc := 0.0
var _n := 0
var _worst := 0.0


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = EYE_SIZES[i]
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 105.0
		cam.near = 0.05
		cam.far = 6000.0
		vp.add_child(cam)
		cam.current = true
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		_vps.append(vp)
		_cams.append(cam)
	print("[VRBench] rendering 2 eyes %s + %s, MSAA 4x" % [EYE_SIZES[0], EYE_SIZES[1]])


func _process(delta: float) -> void:
	var head := XrManager.head_transform()
	for i in 2:
		_cams[i].global_transform = head.translated_local(Vector3((i * 2 - 1) * IPD * 0.5, 0, 0))
	var gpu := 0.0
	for vp in _vps:
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
	_acc += gpu
	_worst = maxf(_worst, gpu)
	_n += 1
	_t += delta
	if _t >= 1.0:
		var avg := _acc / maxf(_n, 1)
		print("[VRBench] GPU both eyes: avg %.2f ms, worst %.2f ms  -> GPU-limit ~%.0f FPS  (90 Hz needs < 11.1 ms)" % [avg, _worst, 1000.0 / maxf(avg, 0.01)])
		_t = 0.0
		_acc = 0.0
		_n = 0
		_worst = 0.0
