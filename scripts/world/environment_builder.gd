class_name EnvironmentBuilder
## Sky, flat olive ground to the horizon and low-poly backdrop scenery.
## Themes: 0 mountains, 1 hills, 2 tall peaks, 3 buildings, 4 snow peaks, 5 mixed.

const GROUND_SIZE := 8000.0


## holes: plan-view polygons (x, z) left open in the ground (TrackPath.ground_holes).
static func build(parent: Node3D, theme: int, track_bounds: AABB, holes: Array = []) -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Palette.SKY_TOP
	sky_mat.sky_horizon_color = Palette.SKY
	sky_mat.sky_curve = 0.25
	sky_mat.ground_bottom_color = Palette.GROUND
	sky_mat.ground_horizon_color = Palette.GROUND
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# diffuse sky light: keeps shadowed areas readable (no black shadows)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.75
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.environment = e
	parent.add_child(env)

	# the sun: directional light = parallel rays from infinity,
	# high and from the side so the car's shadow lands near it
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.add_to_group("sun")
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 0.62
	sun.light_specular = 0.0
	sun.shadow_enabled = Settings.shadows
	sun.shadow_bias = 0.3
	sun.shadow_normal_bias = 3.0
	sun.shadow_blur = 0.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_split_1 = 0.04
	sun.directional_shadow_split_2 = 0.12
	sun.directional_shadow_split_3 = 0.35
	parent.add_child(sun)

	# ground plane (visual + collision), open over tunnel cuts
	var kit := MeshKit.new()
	var g := GROUND_SIZE * 0.5
	var c := track_bounds.get_center()
	var ground_tris := PackedVector3Array()
	GroundMesh.area(Rect2(c.x - g, c.z - g, GROUND_SIZE, GROUND_SIZE), holes, ground_tris)
	for t in range(0, ground_tris.size(), 3):
		kit.tri(ground_tris[t], ground_tris[t + 1], ground_tris[t + 2], Palette.GROUND)
	_ground_marks(kit, track_bounds, holes)
	var gm := kit.build_instance()
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gm.name = "Ground"
	parent.add_child(gm)

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = TrackNode.LAYER_GROUND
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	if holes.is_empty():
		cs.shape = WorldBoundaryShape3D.new()
	else:
		# an infinite plane would fill the tunnels: the ground's own triangles
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(ground_tris)
		cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

	var scenery := _scenery(theme, track_bounds)
	scenery.name = "Scenery"
	parent.add_child(scenery)


## A few darker ground patches for speed/height perception near the track
## (none near a hole: they would cover it).
static func _ground_marks(kit: MeshKit, b: AABB, holes: Array = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1989
	var c := b.get_center()
	var extent := maxf(b.size.x, b.size.z) * 0.9 + 200.0
	var dark := Palette.GROUND.darkened(0.12)
	for i in 70:
		var p := Vector3(c.x + rng.randf_range(-extent, extent), 0.02, c.z + rng.randf_range(-extent, extent))
		var r := rng.randf_range(6.0, 22.0)
		var near_hole := false
		for h in holes:
			for q in h:
				if Vector2(p.x, p.z).distance_to(q) < r + 4.0:
					near_hole = true
					break
		if near_hole:
			continue
		var sides := 6
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			kit.tri(p, p + Vector3(cos(a1), 0, sin(a1)) * r, p + Vector3(cos(a0), 0, sin(a0)) * r, dark)


static func _scenery(theme: int, b: AABB) -> MeshInstance3D:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 64 + theme
	var c := b.get_center()
	var far := maxf(b.size.x, b.size.z) * 0.5 + 900.0
	var count := 32
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.06, 0.06)
		var dist := far + rng.randf_range(0.0, 600.0)
		var p := Vector3(c.x + cos(ang) * dist, 0.0, c.z + sin(ang) * dist)
		var kind := theme
		if theme == 5:
			kind = [0, 2, 3, 4][i % 4]
		match kind:
			0:
				kit.peak(p, rng.randf_range(160, 320), rng.randf_range(120, 260), 5, Palette.ROCK, Color(-1, 0, 0), 0.0, rng.randf() * TAU)
			1:
				kit.peak(p, rng.randf_range(250, 450), rng.randf_range(60, 120), 7, Palette.HILL, Color(-1, 0, 0), 0.0, rng.randf() * TAU)
			2:
				kit.peak(p, rng.randf_range(120, 220), rng.randf_range(260, 480), 4, Palette.ROCK_DARK, Color(-1, 0, 0), 0.0, rng.randf() * TAU)
			3:
				_buildings(kit, rng, p, ang)
			4:
				kit.peak(p, rng.randf_range(150, 300), rng.randf_range(200, 420), 5, Palette.ROCK, Palette.SNOW, 0.35, rng.randf() * TAU)
	var mi := kit.build_instance()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _buildings(kit: MeshKit, rng: RandomNumberGenerator, p: Vector3, ang: float) -> void:
	var basis := Basis(Vector3.UP, -ang)
	for k in rng.randi_range(2, 4):
		var off := basis * Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-60, 60))
		var size := Vector3(rng.randf_range(40, 90), rng.randf_range(40, 160), rng.randf_range(40, 90))
		var col := Palette.BUILDING if k % 2 == 0 else Palette.BUILDING_DARK
		kit.box(p + off + Vector3(0, size.y * 0.5, 0), size, col, basis)
