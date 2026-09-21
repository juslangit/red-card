extends Node

## The game outside the match: settings, the career, and which screen is showing.
##
## An autoload, so every scene can reach it as `Game`. A match is described by a plain
## dictionary — `start_match()` — so a career fixture, a quick match, a training drill and
## a scenario challenge are all the same thing with different fields filled in.

var settings: Settings
var career: Career
## The title sequence plays once a session, not every time you back out to the menu.
var title_seen := false
## What the next Play scene should set up. See `start_match`.
var pending: Dictionary = {}
## What the last one produced, for the report screen.
var last_result: Dictionary = {}

const PLAY := "res://scenes/play.tscn"
const MENU := "res://scenes/menu.tscn"


func _ready() -> void:
	settings = Settings.load_or_default()
	settings.apply()
	career = Career.load_or_new()
	process_mode = Node.PROCESS_MODE_ALWAYS


## Starts a match. Fields:
##   mode       "career" | "quick" | "training" | "scenario"
##   level      venue id
##   home, away club indices into Names.CLUBS
##   half       real seconds per half
##   scenario   a Scenarios id, for training and challenges
func start_match(config: Dictionary) -> void:
	pending = config
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(PLAY)


func to_menu(page := "") -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pending = {"page": page}
	get_tree().change_scene_to_file(MENU)


func half_seconds() -> float:
	return settings.half_minutes * 60.0
