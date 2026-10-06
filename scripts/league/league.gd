class_name League
extends RefCounted
## Four divisions of three drivers. Each season the player races both
## division rivals on both division tracks (4 races); the rivals' race
## against each other and all other divisions are simulated.
## Win = 2 points, fastest lap = 1 point. Top driver goes up, bottom down.
## Winning Division 1 unlocks the Super League.

const PLAYER := -1
const WIN_POINTS := 2
const LAP_POINTS := 1

## divisions[0] = Division 1 (top) ... divisions[3] = Division 4.
var divisions: Array = []
var points := {}
var season := 1
var schedule: Array = []     # [{track, opponent}]
var race_index := 0
var super_league := false
var holes := 0
var last_season_report := ""


static func new_game() -> League:
	var l := League.new()
	l.divisions = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, PLAYER]]
	l.start_season()
	return l


func player_division() -> int:
	for d in 4:
		if PLAYER in divisions[d]:
			return d + 1
	return 4


func rivals() -> Array:
	var res := []
	for id in divisions[player_division() - 1]:
		if id != PLAYER:
			res.append(id)
	return res


func start_season() -> void:
	points.clear()
	for d in divisions:
		for id in d:
			points[id] = 0
	var div := player_division()
	var tracks: Array = TrackLibrary.DIVISION_TRACKS[div]
	var r := rivals()
	schedule = [
		{"track": tracks[0], "opponent": r[0]},
		{"track": tracks[0], "opponent": r[1]},
		{"track": tracks[1], "opponent": r[0]},
		{"track": tracks[1], "opponent": r[1]},
	]
	race_index = 0
	holes = 0


func season_finished() -> bool:
	return race_index >= schedule.size()


func next_race() -> Dictionary:
	if season_finished():
		return {}
	return schedule[race_index]


static func driver_name(id: int) -> String:
	return "DU" if id == PLAYER else Drivers.get_driver(id)["name"]


## result: {won: bool, player_fastest: bool}
func record_player_race(result: Dictionary) -> void:
	var race: Dictionary = next_race()
	if race.is_empty():
		return
	var opp: int = race["opponent"]
	if result.get("won", false):
		points[PLAYER] += WIN_POINTS
	else:
		points[opp] += WIN_POINTS
	if result.get("player_fastest", false):
		points[PLAYER] += LAP_POINTS
	else:
		points[opp] += LAP_POINTS
	holes = result.get("holes", holes)
	race_index += 1


static func simulate_race(a: int, b: int, rng: RandomNumberGenerator) -> Array:
	var sa: float = Drivers.get_driver(a)["skill"] + rng.randf_range(-0.04, 0.04)
	var sb: float = Drivers.get_driver(b)["skill"] + rng.randf_range(-0.04, 0.04)
	var winner := a if sa >= sb else b
	var fastest := a if sa + rng.randf_range(-0.03, 0.03) >= sb else b
	return [winner, fastest]


func standings(div_index: int) -> Array:
	var ids: Array = divisions[div_index].duplicate()
	ids.sort_custom(_ranks_before)
	return ids


func _ranks_before(x: int, y: int) -> bool:
	if points[x] != points[y]:
		return points[x] > points[y]
	return _skill(x) > _skill(y)


func _skill(id: int) -> float:
	return 2.0 if id == PLAYER else float(Drivers.get_driver(id)["skill"])


## Simulates the remaining races, applies promotion/relegation and starts the
## next season. Returns a short report.
func finish_season(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var pdiv := player_division() - 1
	for d in 4:
		var ids: Array = divisions[d]
		var pairs := []
		if d == pdiv:
			var r := rivals()
			pairs = [[r[0], r[1]], [r[0], r[1]]]
		else:
			pairs = [[ids[0], ids[1]], [ids[0], ids[2]], [ids[1], ids[2]], [ids[0], ids[1]], [ids[0], ids[2]], [ids[1], ids[2]]]
		for pair in pairs:
			var res := simulate_race(pair[0], pair[1], rng)
			points[res[0]] += WIN_POINTS
			points[res[1]] += LAP_POINTS

	var table := []
	for d in 4:
		table.append(standings(d))
	var report := ""
	var player_won_div1: bool = pdiv == 0 and table[0][0] == PLAYER
	# promotion / relegation between neighbouring divisions
	var new_divs := []
	for d in 4:
		new_divs.append(table[d].duplicate())
	for d in 3:
		var bottom_upper = table[d][2]
		var top_lower = table[d + 1][0]
		new_divs[d][2] = top_lower
		new_divs[d + 1][0] = bottom_upper
	var player_pos: int = table[pdiv].find(PLAYER) + 1
	report = "SAISON %d: PLATZ %d IN DIVISION %d" % [season, player_pos, pdiv + 1]
	if player_won_div1:
		if not super_league:
			report += " - SUPER LEAGUE FREIGESCHALTET!"
		super_league = true
	elif player_pos == 1 and pdiv > 0:
		report += " - AUFSTIEG!"
	elif player_pos == 3 and pdiv < 3:
		report += " - ABSTIEG"
	divisions = new_divs
	season += 1
	last_season_report = report
	start_season()
	return report


func to_dict() -> Dictionary:
	var pts := {}
	for k in points:
		pts[str(k)] = points[k]
	return {"divisions": divisions, "points": pts, "season": season, "schedule": schedule,
		"race_index": race_index, "super": super_league, "holes": holes, "report": last_season_report}


static func from_dict(d: Dictionary) -> League:
	var l := League.new()
	l.divisions = []
	for div in d["divisions"]:
		var ids := []
		for id in div:
			ids.append(int(id))
		l.divisions.append(ids)
	for k in d["points"]:
		l.points[int(k)] = int(d["points"][k])
	l.season = int(d.get("season", 1))
	l.schedule = []
	for r in d.get("schedule", []):
		var tid := str(r["track"])
		tid = TrackLibrary.LEGACY_IDS.get(tid, tid)
		l.schedule.append({"track": tid, "opponent": int(r["opponent"])})
	l.race_index = int(d.get("race_index", 0))
	l.super_league = bool(d.get("super", false))
	l.holes = int(d.get("holes", 0))
	l.last_season_report = str(d.get("report", ""))
	return l
