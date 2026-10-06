class_name LapTracker
extends RefCounted
## Counts laps by requiring the pieces to be passed in order (no shortcuts).
## Up to two pieces may be skipped at once (short gap pieces flown over).

var piece_count := 1
var next_piece := 1
var laps_done := 0


func _init(count: int, start_piece := 0) -> void:
	piece_count = count
	next_piece = (start_piece + 1) % count


## Feed the current piece; returns true when a lap was completed.
func update(piece: int) -> bool:
	for k in 3:
		if piece == (next_piece + k) % piece_count:
			var completed := false
			for m in k + 1:
				if (next_piece + m) % piece_count == 0:
					completed = true
			next_piece = (piece + 1) % piece_count
			if completed:
				laps_done += 1
			return completed
	return false
