class_name Settings
extends RefCounted

## What the player has chosen about how the game behaves, and where it is kept.
##
## Carried over from Referee For Fun. Written to user:// because it belongs to whoever is
## sitting at the machine, and applied the moment it changes — a setting you have to
## restart for is a setting people assume is broken.

const PATH := "user://settings.cfg"
const DEV_PATH := "user://dev_settings.cfg"

const CROWD_BUS := "Crowd"
const EFFECTS_BUS := "Effects"

var master := 0.85
var crowd := 0.75
var effects := 0.9
## Radians of head turn per pixel of mouse movement.
var sensitivity := 0.0022
const SENSITIVITY_MIN := 0.0008
const SENSITIVITY_MAX := 0.0055
var invert_y := false
var fullscreen := false
## Real minutes per half. Luqman chose short halves; five to eight are offered.
var half_minutes := 6
## How much the camera bobs with each stride, 0 to 1. Some people get motion sick.
var head_bob := 1.0
## Whether the training ground has been visited, so the first match can suggest it.
var trained := false
var bindings := {}


static func path() -> String:
	return DEV_PATH if is_a_dev_run() else PATH


## True when Godot was launched straight into a scene under res://dev/ — a check or a
## look, never the game. Those write their own settings and career, not the player's.
static func is_a_dev_run() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://dev/"):
			return true
	return false


static func load_or_default() -> Settings:
	var settings := Settings.new()
	var file := ConfigFile.new()
	if file.load(path()) != OK:
		return settings
	settings.master = file.get_value("audio", "master", settings.master)
	settings.crowd = file.get_value("audio", "crowd", settings.crowd)
	settings.effects = file.get_value("audio", "effects", settings.effects)
	settings.sensitivity = file.get_value("look", "sensitivity", settings.sensitivity)
	settings.invert_y = file.get_value("look", "invert_y", settings.invert_y)
	settings.head_bob = file.get_value("look", "head_bob", settings.head_bob)
	settings.fullscreen = file.get_value("window", "fullscreen", settings.fullscreen)
	settings.half_minutes = file.get_value("match", "half_minutes", settings.half_minutes)
	settings.trained = file.get_value("player", "trained", settings.trained)
	settings.bindings = file.get_value("controls", "bindings", {})
	return settings


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("audio", "master", master)
	file.set_value("audio", "crowd", crowd)
	file.set_value("audio", "effects", effects)
	file.set_value("look", "sensitivity", sensitivity)
	file.set_value("look", "invert_y", invert_y)
	file.set_value("look", "head_bob", head_bob)
	file.set_value("window", "fullscreen", fullscreen)
	file.set_value("match", "half_minutes", half_minutes)
	file.set_value("player", "trained", trained)
	file.set_value("controls", "bindings", bindings)
	file.save(path())


func apply() -> void:
	ensure_buses()
	Controls.ensure(self)
	_set_bus("Master", master)
	_set_bus(CROWD_BUS, crowd)
	_set_bus(EFFECTS_BUS, effects)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


static func ensure_buses() -> void:
	for name in [CROWD_BUS, EFFECTS_BUS]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var at := AudioServer.bus_count - 1
		AudioServer.set_bus_name(at, name)
		AudioServer.set_bus_send(at, "Master")


static func _set_bus(name: String, amount: float) -> void:
	var at := AudioServer.get_bus_index(name)
	if at < 0:
		return
	AudioServer.set_bus_mute(at, amount <= 0.001)
	AudioServer.set_bus_volume_db(at, linear_to_db(maxf(amount, 0.0001)))
