class_name TrackPreview3D
extends Node3D
## A slowly turning view of a track on a quad in 3D space (menu, below the
## panel): the track and its scenery in a SubViewport with a world of its
## own, a camera circling it. show_track() builds a track once and keeps it
## while the same one is shown.

const SPIN := 0.25          # rad/s
const PITCH := 0.38         # rad, camera above the horizon (flat: the strip is wide)
const FOV := 60.0           # horizontal
const FRAME := 0.012        # m, frame around the picture

var viewport: SubViewport
var quad: MeshInstance3D
var _world: Node3D
var _cam: Camera3D
var _track_id := ""
var _center := Vector3.ZERO
var _dist := 300.0
var _angle := 0.0


func setup(pixel_size: Vector2i, world_size: Vector2) -> TrackPreview3D:
	viewport = SubViewport.new()
	viewport.size = pixel_size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = FOV
	_cam.far = 8000.0
	viewport.add_child(_cam)

	quad = Panel3D.make_quad(world_size, viewport.get_texture())
	add_child(quad)
	# a frame like the menu panel's, just behind the picture
	var frame := Panel3D.make_quad(world_size + Vector2(FRAME, FRAME) * 2.0, null, Palette.LIGHT_BLUE)
	frame.position = Vector3(0, 0, -0.003)
	add_child(frame)
	visible = false
	return self


## Shows track id (builds it if it is not the one already shown).
func show_track(id: String) -> void:
	visible = true
	if id == _track_id:
		return
	_track_id = id
	for c in _world.get_children():
		c.queue_free()
	var def := TrackLibrary.get_def(id)
	var path := TrackPath.new(def)
	_world.add_child(TrackNode.new().build(path))
	EnvironmentBuilder.build(_world, int(def.get("theme", 0)), path.bounds(), path.ground_holes())
	var b := path.bounds()
	_center = b.get_center()
	# the whole track in view from every side: the circle around it across
	# the width, its depth (foreshortened by PITCH) in the low strip
	var r := 0.0
	for i in range(0, path.n, 4):
		r = maxf(r, Vector2(path.center[i].x - _center.x, path.center[i].z - _center.z).length())
	r += TrackPath.HALF_WIDTH
	var half_h := tan(deg_to_rad(FOV * 0.5))
	var half_v := half_h * float(viewport.size.y) / float(viewport.size.x)
	_dist = maxf(r / half_h, (r * sin(PITCH) + b.size.y * 0.5) / half_v) * 1.05
	_place()


func hide_track() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible or _track_id == "":
		return
	_angle += delta * SPIN
	_place()


func _place() -> void:
	var eye := _center + Vector3(sin(_angle) * cos(PITCH), sin(PITCH), cos(_angle) * cos(PITCH)) * _dist
	_cam.look_at_from_position(eye, _center, Vector3.UP)
