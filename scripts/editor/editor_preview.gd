class_name EditorPreview
extends SubViewportContainer
## 3D preview of the track editor's height stage: the track and its scenery
## in a world of its own, a camera orbiting a focus point. The camera
## travels to a new focus or distance smoothly (a real camera move, the
## field of view stays); turning (orbit) is immediate.

const FOCUS_DIST := 140.0       # distance onto a focus point (selection)
const CAM_SPEED := 5.0          # camera travel (1/s)
const FOV := 60.0               # horizontal field of view (deg)

var _world: Node3D
var _cam: Camera3D
var _bounds := AABB()
var _yaw := 0.7
var _pitch := 0.6
var _zoom_dist := 0.0           # set by the wheel (0: automatic)
var _focus = null               # Vector3, or null: the whole track
var _c := Vector3.ZERO          # look-at point and distance now ...
var _d := 0.0
var _target_c := Vector3.ZERO   # ... and where the camera travels to
var _target_d := 0.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var sub := SubViewport.new()
	sub.own_world_3d = true
	add_child(sub)
	_world = Node3D.new()
	sub.add_child(_world)
	_cam = Camera3D.new()
	_cam.far = 6000.0
	_cam.keep_aspect = Camera3D.KEEP_WIDTH   # fov is horizontal
	_cam.fov = FOV
	sub.add_child(_cam)


## Builds the track of path (replacing the one shown).
func build(path: TrackPath) -> void:
	for c in _world.get_children():
		c.queue_free()
	_world.add_child(TrackNode.new().build(path))
	EnvironmentBuilder.build(_world, 0, path.bounds(), path.ground_holes())
	_bounds = path.bounds()
	_retarget()


## What the camera looks at: a point, or null for the whole track.
func set_focus(focus) -> void:
	_focus = focus
	_retarget()


## Turns the view by a mouse movement (pixels).
func orbit(relative: Vector2) -> void:
	_yaw -= relative.x * 0.01
	_pitch = clampf(_pitch + relative.y * 0.01, 0.05, 1.5)
	_aim()


## Wheel: factor < 1 closer, > 1 farther.
func zoom(factor: float) -> void:
	_zoom_dist = _auto_dist() * factor if _zoom_dist <= 0.0 else _zoom_dist * factor
	_retarget()


func _auto_dist() -> float:
	if _focus != null:
		return FOCUS_DIST
	return maxf(_bounds.size.x, _bounds.size.z) * 0.9 + 60.0


func _retarget() -> void:
	_target_c = _focus if _focus != null else _bounds.get_center()
	_target_d = _zoom_dist if _zoom_dist > 0.0 else _auto_dist()
	if _d <= 0.0:      # first view: no travel
		_c = _target_c
		_d = _target_d
	_aim()


func _aim() -> void:
	var eye := _c + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _d
	_cam.look_at_from_position(eye, _c, Vector3.UP)
	_cam.current = true


func _process(dt: float) -> void:
	if not visible or _d <= 0.0:
		return
	if _c.is_equal_approx(_target_c) and is_equal_approx(_d, _target_d):
		return
	var k := 1.0 - exp(-dt * CAM_SPEED)
	_c = _c.lerp(_target_c, k)
	_d = lerpf(_d, _target_d, k)
	if _c.distance_to(_target_c) < 0.05 and absf(_d - _target_d) < 0.05:
		_c = _target_c
		_d = _target_d
	_aim()
