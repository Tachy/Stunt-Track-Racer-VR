class_name GroundMesh
## The flat ground as triangles, with openings over the open tunnel cuts.
## (No autoload references: the headless tests use it.)

## Ground cells along the edge of a hole are refined down to this size
## before they are clipped exactly.
const HOLE_CELL := 2.0


## Ground triangles for rect minus the holes: cells away from every hole
## stay whole, cells over a hole edge split down to HOLE_CELL and are then
## clipped exactly (a cell that small never contains a whole hole).
static func area(r: Rect2, holes: Array, out: PackedVector3Array) -> void:
	var cell := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var touching := []
	for h in holes:
		if not Geometry2D.intersect_polygons(cell, h).is_empty():
			touching.append(h)
	if touching.is_empty():
		_poly(cell, out)
		return
	if r.size.x > HOLE_CELL:
		var half := r.size * 0.5
		for k in 4:
			var off := Vector2(half.x * (k % 2), half.y * (k / 2))
			area(Rect2(r.position + off, half), touching, out)
		return
	var polys := [cell]
	for h in touching:
		var next := []
		for poly in polys:
			next.append_array(Geometry2D.clip_polygons(poly, h))
		polys = next
	for poly in polys:
		_poly(poly, out)


static func _poly(poly: PackedVector2Array, out: PackedVector3Array) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in idx:
		out.append(Vector3(poly[k].x, 0.0, poly[k].y))
