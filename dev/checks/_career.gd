extends Node

## A whole career, played out in numbers.
##
##     Godot --headless --path . res://dev/checks/_career.tscn
##
## Four levels, promotion on the average mark over a short season, and the cup final at the
## end of it. This walks a referee up the ladder — including a season he does not deserve
## promotion from, because failing has to work too — and then checks that the record kept
## on the way adds up, since that record is the only thing the ending has to show.

func _ready() -> void:
	var bad := 0
	var career := Career.new()
	career.fixture_seed = 7

	# Three good matches at the village: up.
	bad += _season(career, [8.4, 8.6, 8.5], "promoted", 1)
	# A poor season at the town: another one there.
	bad += _season(career, [7.9, 8.0, 7.8], "repeat", 1)
	# Then a good one: up.
	bad += _season(career, [8.5, 8.4, 8.6], "promoted", 2)
	bad += _season(career, [8.7, 8.8, 8.4], "promoted", 3)
	# And the final, which ends it however it goes.
	bad += _season(career, [8.9], "champion", 3)

	if not career.finished:
		print("BAD  the cup final did not finish the career")
		bad += 1
	var r := career.record_so_far()
	print("     %d matches, average %.2f, best %.1f, %d yellow %d red, %.0f km"
		% [r.matches, r.average, r.best, r.yellows, r.reds, r.kilometres])
	if r.matches != 13:
		print("BAD  counted %d matches, expected 13" % r.matches)
		bad += 1
	if not is_equal_approx(snappedf(r.best, 0.01), 8.9):
		print("BAD  best mark came out %.2f, expected 8.9" % r.best)
		bad += 1
	if r.yellows != 13 or r.reds != 13:
		print("BAD  cards came out %d yellow %d red, expected 13 of each" % [r.yellows, r.reds])
		bad += 1
	# One entry per level actually finished — the repeated season does not count twice.
	if r.levels.size() != 4:
		print("BAD  %d levels in the record, expected 4" % r.levels.size())
		bad += 1
	for entry in r.levels:
		print("     %s: %.2f" % [Career.LEVEL_TITLES[int(entry.level)], float(entry.average)])
	print("%d career problem(s)" % bad)
	get_tree().quit(1 if bad > 0 else 0)


## Plays a season of marks and checks what the career made of it.
func _season(career: Career, marks: Array, expected: String, level_after: int) -> int:
	var outcome := ""
	for mark: float in marks:
		# Every match: one yellow, one red and ten kilometres, so the totals are countable.
		outcome = career.record({"home": 0, "away": 1}, mark, "1–0",
			{"distance_km": 10.0, "card_list": ["yellow", "red"]})
	var bad := 0
	if outcome != expected:
		print("BAD  season of %s ended '%s', expected '%s'" % [str(marks), outcome, expected])
		bad += 1
	if career.level != level_after:
		print("BAD  at level %d after that season, expected %d" % [career.level, level_after])
		bad += 1
	return bad
