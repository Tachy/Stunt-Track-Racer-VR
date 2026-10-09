class_name TrackLibrary
## The tracks: the eight league tracks (rebuilt freely in the spirit of the
## 1989 originals), the extra release tracks and the ones from the editor.
## Official track data: server/official/<id>.json (see OFFICIAL_DIR).
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

## The official tracks (the league and the extra release tracks) live in
## server/official/<id>.json, in the editor's format: "def" is what the
## game builds, the rest lets the track editor load it (admin mode). The
## online server embeds the very same files.
const OFFICIAL_DIR := "res://server/official"
## Whole-number fields of a definition.
const INT_FIELDS := ["theme", "boost", "boost_super", "division"]

## id -> definition of every official track (loaded once).
static var TRACKS: Dictionary = _load_official()


static func official_path(id: String) -> String:
	return OFFICIAL_DIR.path_join(id + ".json")


## The editor file of an official track ({} if missing).
static func load_official(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(official_path(id))
	var data = JSON.parse_string(text) if text != "" else null
	return data if data is Dictionary else {}


static func is_official(id: String) -> bool:
	return TRACKS.has(id)


static func _load_official() -> Dictionary:
	var out := {}
	for id in ORDER + CUSTOM:
		var data := load_official(id)
		if data.get("def") is Dictionary:
			var def: Dictionary = data["def"]
			for k in INT_FIELDS:      # JSON knows no integers
				if def.has(k):
					def[k] = int(def[k])
			out[id] = def
		else:
			push_error("[TrackLibrary] official track missing or broken: %s" % official_path(id))
	return out


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


## Online: the editor track of another player, kept for this race only
## (never saved): {name, def}. Its id is SHARED_ID.
const SHARED_ID := "net/shared"
const SHARED_MAX_SIZE := 256 * 1024
static var shared := {}


## Online: a custom track to send along with an offer (name and def as
## compact JSON, deflated); empty if there is none.
static func share_data(id: String) -> PackedByteArray:
	var data := load_custom(id)
	if not data.get("def") is Dictionary:
		return PackedByteArray()
	var out := {"name": data.get("name", id.trim_prefix(CUSTOM_PREFIX)), "def": data["def"]}
	return JSON.stringify(out).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)


## Online: keeps a track received with share_data as SHARED_ID (replacing
## the one before) and returns that id; "" if the data is broken.
static func install_shared(blob: PackedByteArray) -> String:
	if blob.is_empty():
		return ""
	var text := blob.decompress_dynamic(SHARED_MAX_SIZE, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if not (data is Dictionary and data.get("def") is Dictionary and data["def"].get("pieces") is Array):
		return ""
	shared = {"name": str(data.get("name", "")), "def": data["def"]}
	return SHARED_ID


static func clear_shared() -> void:
	shared = {}


static func get_def(id: String) -> Dictionary:
	var d: Dictionary
	if is_custom(id):
		d = load_custom(id).get("def", {})
	elif id == SHARED_ID:
		d = shared.get("def", {}).duplicate(true)
	else:
		d = TRACKS[id].duplicate(true)
	d["id"] = id
	return d


static func display_name(id: String) -> String:
	if is_custom(id):
		return str(load_custom(id).get("name", id.trim_prefix(CUSTOM_PREFIX)))
	if id == SHARED_ID:
		return str(shared.get("name", ""))
	return TRACKS[id]["name"]


static func division_of(id: String) -> int:
	if is_custom(id) or id == SHARED_ID:
		return 1
	if TRACKS.has(id) and TRACKS[id].has("division"):
		return int(TRACKS[id]["division"])
	for div in DIVISION_TRACKS:
		if id in DIVISION_TRACKS[div]:
			return div
	return 4
