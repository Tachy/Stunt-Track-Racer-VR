class_name TrackLibrary
## The eight tracks, rebuilt freely in the spirit of the 1989 originals.
## No original track data is used.
##
## Piece fields:
##   t      "S" straight, "L"/"R" curve
##   l      straight length in metres
##   r, a   curve radius (m) and angle (deg), defaults 55 / 90
##   h      height at the END of the piece (default: unchanged)
##   p      height profile: "ramp" (smoothstep, default), "lin", "kick"
##          (steepest at the end -> take-off lip), "land" (steepest at start)
##   bump   extra hump amplitude (sin profile, 0 at both ends)
##   bank   banking peak in degrees (sin profile; + = left edge higher)
##   gap    no road on this piece (jump!)
##   (pits: a short steep wall down, a pit floor, a steep wall up - see
##    TrackPath pit detection)
##   bridge drawbridge leaves on this piece
##   no_crane  never put the car back here
##   (tunnels: a negative h takes the road below the ground - an open cut
##    first, then a covered tunnel; see TrackPath tunnel detection)
##
## The league tracks are own designs in the spirit of the 1989 originals
## (irregular layouts, steep banking, pits with black walls); straight lengths
## were solved offline so every loop closes exactly.

const ORDER := [
	"first_flight", "camel_back",          # Division 4
	"mega_ramp", "stone_hopper",       # Division 3
	"big_dipper", "the_tower",       # Division 2
	"bridge_run", "ski_flyer",           # Division 1
]

## Track ids used by saves of earlier versions.
const LEGACY_IDS := {
	"little_ramp": "first_flight",
	"hump_back": "camel_back",
	"big_ramp": "mega_ramp",
	"stepping_stones": "stone_hopper",
	"roller_coaster": "big_dipper",
	"high_jump": "the_tower",
	"draw_bridge": "bridge_run",
	"ski_jump": "ski_flyer",
	"custom_1": "loop_and_jump",
}

## Extra tracks (practice only, not part of the league).
const CUSTOM := ["loop_and_jump", "grand_tour"]

const DIVISION_TRACKS := {
	4: ["first_flight", "camel_back"],
	3: ["mega_ramp", "stone_hopper"],
	2: ["big_dipper", "the_tower"],
	1: ["bridge_run", "ski_flyer"],
}

const TRACKS := {
	# Long figure eight with everything: camel humps, two jumps, a pit, the
	# drawbridge, a loop and a 400 m tunnel with an S-bend that passes 17 m
	# under the start straight. Straights solved so the lap closes exactly.
	"grand_tour": {
		"name": "Grand Tour", "theme": 0, "base": 8.0, "boost": 70, "boost_super": 55, "division": 1,
		"pieces": [
			{"t": "S", "l": 120},                                  # start straight
			{"t": "S", "l": 80, "bump": 4.0},                      # camel humps
			{"t": "S", "l": 80, "bump": 4.0},
			{"t": "S", "l": 80, "bump": 3.0},
			{"t": "L", "r": 50, "bank": -36.0},
			{"t": "S", "l": 40},
			{"t": "S", "l": 30, "h": 11.0, "p": "kick"},           # jump 1
			{"t": "S", "l": 14, "h": 9.0, "p": "lin", "gap": true},
			{"t": "S", "l": 30, "h": 8.0, "p": "land"},
			{"t": "S", "l": 40},
			{"t": "L", "r": 50, "bank": -36.0},
			{"t": "S", "l": 30},
			{"t": "S", "l": 30, "h": 10.0, "p": "kick"},           # pit
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 12, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 9.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 40, "h": 8.0, "p": "land"},
			{"t": "S", "l": 40},
			{"t": "S", "l": 80, "h": 20.0},                        # up to the drawbridge
			{"t": "S", "l": 40},
			{"t": "S", "l": 60, "bridge": true},
			{"t": "S", "l": 40},
			{"t": "S", "l": 80, "h": 8.0},
			{"t": "L", "r": 50, "bank": -36.0},
			{"t": "S", "l": 40},
			{"t": "S", "l": 100, "h": -9.0},                       # down into the cut
			{"t": "S", "l": 200},                                  # tunnel, under the start straight
			{"t": "R", "r": 70, "a": 35, "bank": 14.0},            # S-bend in the tunnel
			{"t": "L", "r": 70, "a": 35, "bank": -14.0},
			{"t": "S", "l": 120, "bump": 1.2},                     # waves in the tunnel
			{"t": "S", "l": 60},
			{"t": "S", "l": 100, "h": 6.0},                        # climb out
			{"t": "S", "l": 30, "h": 9.0, "p": "kick"},            # jump 2
			{"t": "S", "l": 14, "h": 7.0, "p": "lin", "gap": true},
			{"t": "S", "l": 30, "h": 6.0, "p": "land"},
			{"t": "S", "l": 40},
			{"t": "R", "r": 50, "bank": 36.0},
			{"t": "S", "l": 156.68},
			{"t": "S", "l": 70},
			{"t": "O", "side": 1},                                 # loop
			{"t": "S", "l": 70},
			{"t": "R", "r": 50, "bank": 36.0},
			{"t": "S", "l": 549.3, "h": 8.0},
			{"t": "R", "r": 50, "bank": 36.0},
			{"t": "S", "l": 520},                                  # back over the tunnel
		],
	},
	# Figure eight: the north-south branch crosses the east-west branch on a
	# deck 10 m above it (underpass), two loops, a jump and steep banking.
	"loop_and_jump": {
		"name": "Loop and Jump", "theme": 5, "base": 12.0, "boost": 60, "boost_super": 45, "division": 1,
		"pieces": [
			{"t": "S", "l": 80},                                   # over the underpass
			{"t": "S", "l": 30},
			{"t": "S", "l": 110, "h": 7.0},
			{"t": "L", "r": 40, "bank": -35.0},
			{"t": "S", "l": 80},
			{"t": "O", "side": 1},                                 # loop 1
			{"t": "S", "l": 80},
			{"t": "L", "r": 40, "bank": -35.0},
			{"t": "S", "l": 10},
			{"t": "S", "l": 30, "h": 9.5, "p": "kick"},
			{"t": "S", "l": 12, "h": 8.0, "p": "lin", "gap": true},
			{"t": "S", "l": 28.5, "h": 7.0, "p": "land"},
			{"t": "S", "l": 25, "h": 6.0},                         # run-out after the jump
			{"t": "L", "r": 40, "bank": -30.0, "h": 4.0},
			{"t": "S", "l": 100, "h": 1.5},
			{"t": "S", "l": 94.5},
			{"t": "S", "l": 30},                                   # underpass
			{"t": "S", "l": 110, "h": 8.0},
			{"t": "R", "r": 40, "bank": 35.0},
			{"t": "S", "l": 80},
			{"t": "O", "side": -1},                                # loop 2
			{"t": "S", "l": 80},
			{"t": "R", "r": 40, "bank": 35.0},
			{"t": "S", "l": 105.5, "bump": 4.0},
			{"t": "R", "r": 40, "bank": 35.0},
			{"t": "S", "l": 114.5, "h": 12.0},
		],
	},
	"first_flight": {
		"name": "First Flight", "theme": 0, "base": 6.0, "boost": 40, "boost_super": 30,
		"pieces": [
			{"t": "S", "l": 80},
			{"t": "S", "l": 60},
			{"t": "S", "l": 40, "h": 9.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 3.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 14, "h": 3.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 8.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 50, "h": 6.0, "p": "land"},
			{"t": "S", "l": 80},
			{"t": "R", "r": 40, "a": 120, "bank": 36.0},
			{"t": "S", "l": 90},
			{"t": "S", "l": 30, "h": 8.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 3.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 10, "h": 3.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 7.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 40, "h": 6.0, "p": "land"},
			{"t": "S", "l": 154},
			{"t": "R", "r": 40, "a": 120, "bank": 36.0},
			{"t": "S", "l": 120, "bump": 3.0},
			{"t": "S", "l": 210},
			{"t": "R", "r": 40, "a": 120, "bank": 36.0},
		],
	},
	"camel_back": {
		"name": "Camel Back", "theme": 1, "base": 7.0, "boost": 40, "boost_super": 30,
		"pieces": [
			{"t": "S", "l": 60},
			{"t": "S", "l": 80, "bump": 4.5},
			{"t": "S", "l": 80, "bump": 4.5},
			{"t": "S", "l": 70, "bump": 3.0},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 126.43},
			{"t": "R", "r": 50, "a": 45, "bank": 36.0},
			{"t": "S", "l": 80},
			{"t": "R", "r": 50, "a": 45, "bank": 36.0},
			{"t": "S", "l": 40},
			{"t": "S", "l": 80, "bump": 3.5},
			{"t": "S", "l": 80, "bump": 3.5},
			{"t": "S", "l": 60},
			{"t": "S", "l": 28.43},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 30, "h": 10.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 12, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 9.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 60, "h": 7.0, "p": "land"},
			{"t": "S", "l": 80},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
		],
	},
	"mega_ramp": {
		"name": "Mega Ramp", "theme": 2, "base": 6.0, "boost": 45, "boost_super": 34,
		"pieces": [
			{"t": "S", "l": 60},
			{"t": "S", "l": 90, "h": 14.0},
			{"t": "S", "l": 30, "h": 16.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 18, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 14.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 90, "h": 7.0},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 60},
			{"t": "L", "r": 40, "a": 45, "bank": -30},
			{"t": "S", "l": 50},
			{"t": "R", "r": 40, "a": 45, "bank": 30},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 30},
			{"t": "S", "l": 90, "h": 15.0},
			{"t": "S", "l": 30, "h": 17.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 16, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 15.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 90, "h": 6.0},
			{"t": "S", "l": 150.79, "bump": 3.0},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 211.92, "bump": 4.0},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
		],
	},
	"stone_hopper": {
		"name": "Stone Hopper", "theme": 3, "base": 7.0, "boost": 45, "boost_super": 34,
		"pieces": [
			{"t": "S", "l": 60},
			{"t": "S", "l": 50, "h": 12.0},
			{"t": "S", "l": 30, "h": 13.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 8, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 11.5, "p": "lin", "no_crane": true},
			{"t": "S", "l": 25},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 8, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 10.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 25},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 8, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 8.5, "p": "lin", "no_crane": true},
			{"t": "S", "l": 25},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 8, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 7.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 60},
			{"t": "S", "l": 40},
			{"t": "R", "r": 40, "a": 90, "bank": 36.0},
			{"t": "S", "l": 73},
			{"t": "L", "r": 40, "a": 90, "bank": -36.0},
			{"t": "S", "l": 40},
			{"t": "R", "r": 40, "a": 90, "bank": 36.0},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 486, "bump": 4.0},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 50},
			{"t": "S", "l": 30, "h": 9.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 3.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 12, "h": 3.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 8.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 50, "h": 7.0, "p": "land"},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
		],
	},
	"big_dipper": {
		"name": "Big Dipper", "theme": 5, "base": 10.0, "boost": 50, "boost_super": 38,
		"pieces": [
			{"t": "S", "l": 60},
			{"t": "S", "l": 80, "h": 26.0},
			{"t": "S", "l": 80, "h": 12.0},
			{"t": "S", "l": 70, "h": 20.0},
			{"t": "R", "r": 40, "a": 90, "h": 20.0, "bank": 36.0},
			{"t": "S", "l": 80, "h": 32.0},
			{"t": "S", "l": 80, "h": 14.0},
			{"t": "L", "r": 28, "a": 180, "h": 14.0, "bank": -38},
			{"t": "S", "l": 70, "h": 24.0},
			{"t": "S", "l": 90, "h": 10.0},
			{"t": "S", "l": 70, "h": 18.0},
			{"t": "R", "r": 28, "a": 180, "h": 18.0, "bank": 38},
			{"t": "S", "l": 80, "h": 34.0},
			{"t": "S", "l": 80, "h": 16.0},
			{"t": "S", "l": 60, "h": 10.0},
			{"t": "S", "l": 120, "bump": 5.0},
			{"t": "R", "r": 40, "a": 90, "h": 10.0, "bank": 36.0},
			{"t": "S", "l": 402, "bump": 8.0},
			{"t": "R", "r": 40, "a": 90, "bank": 36.0},
			{"t": "S", "l": 270},
			{"t": "R", "r": 40, "a": 90, "bank": 36.0},
		],
	},
	"the_tower": {
		"name": "The Tower", "theme": 4, "base": 7.0, "boost": 50, "boost_super": 38,
		"pieces": [
			{"t": "S", "l": 60},
			{"t": "S", "l": 120, "h": 18.0},
			{"t": "S", "l": 30, "h": 21.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 6.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 12, "h": 6.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 22.5, "p": "lin", "no_crane": true},
			{"t": "S", "l": 3},
			{"t": "S", "l": 3, "h": 6.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 14, "h": 6.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 20.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 80, "h": 8.0, "p": "land"},
			{"t": "S", "l": 50},
			{"t": "R", "r": 40, "a": 135, "bank": 36.0},
			{"t": "S", "l": 294.91, "bump": 4.0},
			{"t": "R", "r": 45, "a": 45, "bank": 36.0},
			{"t": "S", "l": 168.93, "bump": 3.0},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 70, "h": 12.0},
			{"t": "S", "l": 70, "h": 7.0},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
		],
	},
	"bridge_run": {
		"name": "Bridge Run", "theme": 3, "base": 8.0, "boost": 55, "boost_super": 42,
		"pieces": [
			{"t": "S", "l": 60},
			{"t": "S", "l": 80, "h": 20.0},
			{"t": "S", "l": 40},
			{"t": "S", "l": 60, "bridge": true},
			{"t": "S", "l": 40},
			{"t": "S", "l": 80, "h": 9.0},
			{"t": "R", "r": 45, "a": 60, "bank": 36.0},
			{"t": "S", "l": 60},
			{"t": "S", "l": 30, "h": 12.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 14, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 11.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 50, "h": 9.0, "p": "land"},
			{"t": "S", "l": 40},
			{"t": "R", "r": 45, "a": 60, "bank": 36.0},
			{"t": "S", "l": 80},
			{"t": "R", "r": 45, "a": 60, "bank": 36.0},
			{"t": "S", "l": 370, "bump": 4.0},
			{"t": "R", "r": 45, "a": 60, "bank": 36.0},
			{"t": "S", "l": 50},
			{"t": "S", "l": 30, "h": 12.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 4.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 14, "h": 4.0, "no_crane": true},
			{"t": "S", "l": 3, "h": 11.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 50, "h": 8.0, "p": "land"},
			{"t": "S", "l": 40},
			{"t": "R", "r": 45, "a": 60, "bank": 36.0},
			{"t": "S", "l": 90},
			{"t": "R", "r": 45, "a": 60, "bank": 36.0},
		],
	},
	"ski_flyer": {
		"name": "Ski Flyer", "theme": 4, "base": 8.0, "boost": 55, "boost_super": 42,
		"pieces": [
			{"t": "S", "l": 50},
			{"t": "S", "l": 130, "h": 45.0},
			{"t": "S", "l": 25},
			{"t": "S", "l": 70, "h": 26.0},
			{"t": "S", "l": 25, "h": 28.0, "p": "kick"},
			{"t": "S", "l": 3, "h": 21.0, "p": "lin", "no_crane": true},
			{"t": "S", "l": 110, "h": 8.0},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 90, "bank": 36.0},
			{"t": "S", "l": 111.21, "bump": 5.0},
			{"t": "R", "r": 45, "a": 135, "bank": 36.0},
			{"t": "S", "l": 60},
			{"t": "L", "r": 45, "a": 45, "bank": -30},
			{"t": "S", "l": 324.51, "bump": 4.0},
			{"t": "R", "r": 45, "a": 45, "bank": 30},
			{"t": "S", "l": 60},
			{"t": "R", "r": 45, "a": 135, "bank": 36.0},
		],
	},
}


## Tracks built in the editor live in user://tracks/<name>.json; their id is
## "custom/<name>".
const CUSTOM_DIR := "user://tracks"
const CUSTOM_PREFIX := "custom/"


static func is_custom(id: String) -> bool:
	return id.begins_with(CUSTOM_PREFIX)


## Ids of the saved editor tracks that are closed (drivable).
static func custom_ids() -> Array:
	var ids := []
	if not DirAccess.dir_exists_absolute(CUSTOM_DIR):
		return ids
	var files := DirAccess.get_files_at(CUSTOM_DIR)
	files.sort()
	for f in files:
		if f.ends_with(".json"):
			var data := load_custom(CUSTOM_PREFIX + f.get_basename())
			if data.get("closed", false):
				ids.append(CUSTOM_PREFIX + f.get_basename())
	return ids


static func custom_path(id: String) -> String:
	return CUSTOM_DIR.path_join(id.trim_prefix(CUSTOM_PREFIX) + ".json")


## Deletes the editor file of a custom track; false if there is none.
static func delete_custom(id: String) -> bool:
	return is_custom(id) and FileAccess.file_exists(custom_path(id)) 		and DirAccess.remove_absolute(custom_path(id)) == OK


## The editor file of a custom track ({} if missing).
static func load_custom(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(custom_path(id))
	var data = JSON.parse_string(text) if text != "" else null
	return data if data is Dictionary else {}


static func get_def(id: String) -> Dictionary:
	var d: Dictionary
	if is_custom(id):
		d = load_custom(id).get("def", {})
	else:
		d = TRACKS[id].duplicate(true)
	d["id"] = id
	return d


static func display_name(id: String) -> String:
	if is_custom(id):
		return str(load_custom(id).get("name", id.trim_prefix(CUSTOM_PREFIX)))
	return TRACKS[id]["name"]


static func division_of(id: String) -> int:
	if is_custom(id):
		return 1
	if TRACKS.has(id) and TRACKS[id].has("division"):
		return TRACKS[id]["division"]
	for div in DIVISION_TRACKS:
		if id in DIVISION_TRACKS[div]:
			return div
	return 4
