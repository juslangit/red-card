class_name Career
extends RefCounted

## A referee's career, from the village field to the cup final.
##
## Four levels, one per ground. Each level is a short season of fixtures; the assessor's
## average mark over the season decides promotion, the way referees really move up — on
## their marks, not on how many matches they have done. 8.3 is the bar, which is the
## "expected standard" band and a little over.

const PATH := "user://career.cfg"
const DEV_PATH := "user://dev_career.cfg"

const LEVELS := ["village", "town", "league", "final"]
const LEVEL_TITLES := ["Sunday League", "County League", "National League", "Cup Final"]
const MATCHES_PER_LEVEL := [3, 3, 3, 1]
const PROMOTION_MARK := 8.3

var referee_name := "Referee"
var level := 0
var marks: Array = []          # marks this season, at this level
var history: Array = []        # {level, home, away, mark, score}
var finished := false          # refereed the final
var fixture_seed := 1


static func path() -> String:
	return DEV_PATH if Settings.is_a_dev_run() else PATH


static func load_or_new() -> Career:
	var career := Career.new()
	var file := ConfigFile.new()
	if file.load(path()) != OK:
		return career
	career.referee_name = file.get_value("career", "name", career.referee_name)
	career.level = file.get_value("career", "level", 0)
	career.marks = file.get_value("career", "marks", [])
	career.history = file.get_value("career", "history", [])
	career.finished = file.get_value("career", "finished", false)
	career.fixture_seed = file.get_value("career", "seed", 1)
	return career


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("career", "name", referee_name)
	file.set_value("career", "level", level)
	file.set_value("career", "marks", marks)
	file.set_value("career", "history", history)
	file.set_value("career", "finished", finished)
	file.set_value("career", "seed", fixture_seed)
	file.save(path())


func reset() -> void:
	level = 0
	marks = []
	history = []
	finished = false
	fixture_seed = randi() % 1000 + 1
	save()


func level_id() -> String:
	return LEVELS[level]


func title() -> String:
	return LEVEL_TITLES[level]


func matches_this_season() -> int:
	return MATCHES_PER_LEVEL[level]


## The next fixture: two different clubs, chosen from the seed and how far in we are.
func next_fixture() -> Dictionary:
	var n := history.size() + fixture_seed
	var home := (n * 3) % Names.CLUBS.size()
	var away := Names.clash_free(home, home + 1 + (n % 5))
	if away == home:
		away = (home + 1) % Names.CLUBS.size()
	return {"mode": "career", "level": level_id(), "home": home, "away": away}


func average() -> float:
	if marks.is_empty():
		return 0.0
	var total := 0.0
	for mk in marks:
		total += float(mk)
	return total / marks.size()


## Records a finished match and settles the season if it is over. Returns what happened:
## "continue", "promoted", "repeat" (season again at the same level) or "champion".
func record(fixture: Dictionary, mark: float, score: String) -> String:
	marks.append(mark)
	history.append({"level": level, "home": fixture.home, "away": fixture.away, "mark": mark, "score": score})
	var outcome := "continue"
	if marks.size() >= matches_this_season():
		if level == LEVELS.size() - 1:
			finished = true
			outcome = "champion"
		elif average() >= PROMOTION_MARK:
			level += 1
			outcome = "promoted"
		else:
			outcome = "repeat"
		marks = []
	save()
	return outcome
