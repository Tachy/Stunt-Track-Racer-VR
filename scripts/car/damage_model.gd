class_name DamageModel
extends RefCounted
## The crack in the roll-cage bar. 0 = intact, 1 = wrecked.
## Holes from heavy crashes persist for the season and make the crack grow
## faster.

signal changed
signal hole_added
signal wrecked

const MAX_HOLES := 8
const HOLE_FACTOR := 0.15

var crack := 0.0
var holes := 0
var is_wrecked := false
var hole_threshold := 0.1


func _init(initial_holes := 0) -> void:
	holes = initial_holes


func multiplier() -> float:
	return 1.0 + holes * HOLE_FACTOR


## Adds raw damage; returns the effective amount applied.
func hit(amount: float) -> float:
	if is_wrecked or amount <= 0.0:
		return 0.0
	var eff := amount * multiplier()
	crack = minf(1.0, crack + eff)
	if amount >= hole_threshold and holes < MAX_HOLES:
		holes += 1
		hole_added.emit()
	changed.emit()
	if crack >= 1.0:
		is_wrecked = true
		wrecked.emit()
	return eff
