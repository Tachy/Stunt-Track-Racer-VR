extends Node
## Game progress (league), the pending race request and the last result.

const SAVE_PATH := "user://save.json"

var league: League
## {track, opponent (driver index or -1 for none), league (bool), super (bool), holes}
var request := {}
var last_result := {}


func _ready() -> void:
	load_game()


func has_league() -> bool:
	return league != null


func new_league() -> void:
	league = League.new_game()
	save_game()


func league_request() -> Dictionary:
	if league == null:
		new_league()
	if league.season_finished():
		league.finish_season()
		save_game()
	var r := league.next_race()
	return {"track": r["track"], "opponent": r["opponent"], "league": true,
		"super": league.super_league, "holes": league.holes}


func practice_request(track: String, with_opponent: bool) -> Dictionary:
	var div := TrackLibrary.division_of(track)
	var opp := -1
	if with_opponent:
		# a rival from the track's division
		opp = [9, 10, 6, 7, 3, 4, 0, 1][(4 - div) * 2 + randi() % 2]
	return {"track": track, "opponent": opp, "league": false,
		"super": league != null and league.super_league, "holes": 0}


## result: {won, player_fastest, wrecked, holes, player_best, opp_best, ...}
func apply_result(result: Dictionary) -> void:
	last_result = result
	if request.get("league", false) and league != null:
		league.record_player_race(result)
		if league.season_finished():
			result["season_report"] = league.finish_season()
		save_game()


func save_game() -> void:
	if league == null:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(league.to_dict()))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		league = League.from_dict(data)
