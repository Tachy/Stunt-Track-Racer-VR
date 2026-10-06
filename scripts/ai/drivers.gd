class_name Drivers
## The eleven league opponents. Flags as in the original game:
## push (shoves you), obstruct (blocks you), edge (drives near the edge),
## wheelie (lifts the nose when accelerating).

const LIST := [
	{"name": "Hot Rod", "skill": 0.97, "flags": ["push", "obstruct"], "color": "#dd7711"},
	{"name": "Whizz Kid", "skill": 0.955, "flags": ["push"], "color": "#2266dd"},
	{"name": "Bad Guy", "skill": 0.94, "flags": ["push", "obstruct"], "color": "#222222"},
	{"name": "The Dodger", "skill": 0.925, "flags": ["push"], "color": "#22aa55"},
	{"name": "Big Ed", "skill": 0.91, "flags": ["push", "edge", "wheelie", "obstruct"], "color": "#884422"},
	{"name": "Max Boost", "skill": 0.895, "flags": ["wheelie"], "color": "#ffcc00"},
	{"name": "Dare Devil", "skill": 0.88, "flags": ["push"], "color": "#aa22aa"},
	{"name": "High Flyer", "skill": 0.865, "flags": ["wheelie"], "color": "#55bbff"},
	{"name": "Bully Boy", "skill": 0.85, "flags": ["edge", "obstruct"], "color": "#666666"},
	{"name": "Jumping Jack", "skill": 0.835, "flags": [], "color": "#99bb33"},
	{"name": "Road Hog", "skill": 0.82, "flags": ["edge"], "color": "#ee4488"},
]


static func get_driver(index: int) -> Dictionary:
	return LIST[clampi(index, 0, LIST.size() - 1)]
