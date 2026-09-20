class_name Controls
extends RefCounted

## Every verb the referee has, for the keyboard, the mouse and the pad.
##
## The pattern is Referee For Fun's (2026-09-18): actions are installed at run time, so
## the dev checks that load a match scene directly get them too, and any key can be
## rebound from the settings screen without two verbs ending up on one key.
##
## The referee's body is the controller here. Moving is WASD and the left stick; looking
## is the mouse, the right stick or the arrow keys. The two most important verbs sit under
## the fingers that are already on the mouse: the whistle is the left button and pointing
## is the right, because a referee's whole vocabulary is a whistle and an arm.
##
## Every one of them is also on a key. Luqman played it on 2026-09-20 and asked for the
## game to be keyboard friendly rather than mouse-only, and he was right: the whistle and
## the point were on the mouse buttons alone, and looking around — which pointing depends
## on, since you give the restart you are looking at — could only be done with a mouse.
## Whistle is F and point is E, both beside the hand already on WASD, and the arrow keys
## turn your head. dev/checks/_controls.tscn holds it to that: every verb reachable from
## the keyboard, and no two verbs on one key.

const UNBOUND := 0

const DEFAULTS := {
	&"rc_pause": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START], "label": "Pause", "fixed": true},
	&"rc_forward": {"keys": [KEY_W], "axes": [[JOY_AXIS_LEFT_Y, -1.0]], "label": "Move forward"},
	&"rc_back": {"keys": [KEY_S], "axes": [[JOY_AXIS_LEFT_Y, 1.0]], "label": "Move back"},
	&"rc_left": {"keys": [KEY_A], "axes": [[JOY_AXIS_LEFT_X, -1.0]], "label": "Move left"},
	&"rc_right": {"keys": [KEY_D], "axes": [[JOY_AXIS_LEFT_X, 1.0]], "label": "Move right"},
	&"rc_sprint": {"keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_LEFT_STICK], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]], "label": "Sprint"},
	&"rc_whistle": {"keys": [KEY_F], "mouse": [MOUSE_BUTTON_LEFT], "buttons": [JOY_BUTTON_A], "label": "Whistle (hold: long whistle)"},
	&"rc_point": {"keys": [KEY_E], "mouse": [MOUSE_BUTTON_RIGHT], "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "label": "Point — give the restart you are pointing at"},
	&"rc_advantage": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_X], "label": "Advantage — play on"},
	&"rc_yellow": {"keys": [KEY_Y], "buttons": [JOY_BUTTON_DPAD_UP], "label": "Yellow card"},
	&"rc_red": {"keys": [KEY_R], "buttons": [JOY_BUTTON_DPAD_DOWN], "label": "Red card"},
	&"rc_wave": {"keys": [KEY_X], "buttons": [JOY_BUTTON_DPAD_LEFT], "label": "Wave the flag down"},
	&"rc_indirect": {"keys": [KEY_Q], "buttons": [JOY_BUTTON_LEFT_SHOULDER], "label": "Arm up — indirect free kick"},
	&"rc_drop": {"keys": [KEY_B], "buttons": [JOY_BUTTON_DPAD_RIGHT], "label": "Dropped ball"},
	&"rc_sub": {"keys": [KEY_U], "buttons": [JOY_BUTTON_B], "label": "Allow substitution"},
	&"rc_calm": {"keys": [KEY_C], "buttons": [JOY_BUTTON_Y], "label": "Calm them down — a word, and back off"},
	&"rc_watch": {"keys": [KEY_TAB], "buttons": [JOY_BUTTON_BACK], "label": "Look at your watch (hold)"},
	&"rc_notebook": {"keys": [KEY_N], "buttons": [JOY_BUTTON_RIGHT_STICK], "label": "Notebook"},
	# Turning your head without a mouse. The stick is read straight from the pad's right
	# axis in Referee, which is why these carry no axes of their own.
	&"rc_look_left": {"keys": [KEY_LEFT], "label": "Look left"},
	&"rc_look_right": {"keys": [KEY_RIGHT], "label": "Look right"},
	&"rc_look_up": {"keys": [KEY_UP], "label": "Look up"},
	&"rc_look_down": {"keys": [KEY_DOWN], "label": "Look down"},
}

const ORDER := [&"rc_whistle", &"rc_point", &"rc_advantage", &"rc_yellow", &"rc_red",
	&"rc_wave", &"rc_indirect", &"rc_drop", &"rc_sub", &"rc_calm", &"rc_watch", &"rc_notebook",
	&"rc_sprint", &"rc_forward", &"rc_back", &"rc_left", &"rc_right",
	&"rc_look_left", &"rc_look_right", &"rc_look_up", &"rc_look_down"]


static func ensure(settings: Settings = null) -> void:
	for action: StringName in DEFAULTS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
			_fit(action, DEFAULTS[action])
	if settings != null:
		apply(settings)


static func apply(settings: Settings) -> void:
	for action: StringName in DEFAULTS:
		if DEFAULTS[action].get("fixed", false):
			continue
		var chosen: int = int(settings.bindings.get(String(action), -1))
		if chosen < 0:
			continue
		_fit(action, DEFAULTS[action], chosen)


static func unbound(settings: Settings) -> Array[StringName]:
	var loose: Array[StringName] = []
	for action in ORDER:
		if int(settings.bindings.get(String(action), -1)) == int(UNBOUND):
			loose.append(action)
	return loose


## Rebinds one verb to one key, and reports what it displaced so the screen can say so.
static func rebind(settings: Settings, action: StringName, keycode: Key) -> StringName:
	var clash := &""
	for other: StringName in DEFAULTS:
		if other == action or DEFAULTS[other].get("fixed", false):
			continue
		if _key_of(settings, other) == keycode:
			clash = other
			settings.bindings[String(other)] = int(UNBOUND)
			_fit(other, DEFAULTS[other], int(UNBOUND))
	settings.bindings[String(action)] = int(keycode)
	_fit(action, DEFAULTS[action], keycode)
	settings.save()
	return clash


static func _key_of(settings: Settings, action: StringName) -> Key:
	var chosen: int = int(settings.bindings.get(String(action), -1))
	if chosen >= 0:
		return chosen as Key
	var keys: Array = DEFAULTS[action].get("keys", [])
	return (keys[0] if not keys.is_empty() else KEY_NONE) as Key


## The long spelling, for the pause screen and the settings list. A verb that has both a
## key and a mouse button says both: the keyboard was added without taking the mouse away,
## and a player who has been clicking all along should not have to guess that it still works.
static func spelling(settings: Settings, action: StringName) -> String:
	var key := _key_of(settings, action)
	var mouse: Array = DEFAULTS[action].get("mouse", [])
	var click := ""
	if not mouse.is_empty():
		click = "left click" if int(mouse[0]) == MOUSE_BUTTON_LEFT else "right click"
	if key == KEY_NONE:
		return click.capitalize() if click != "" else "—"
	return "%s  or %s" % [OS.get_keycode_string(key), click] if click != "" else OS.get_keycode_string(key)


## The short name of a verb for an on-screen prompt: "LMB/F", "Y", "SPACE".
static func short(settings: Settings, action: StringName) -> String:
	var key := _key_of(settings, action)
	var mouse: Array = DEFAULTS[action].get("mouse", [])
	var click := ""
	if not mouse.is_empty():
		click = "LMB" if int(mouse[0]) == MOUSE_BUTTON_LEFT else "RMB"
	if key == KEY_NONE:
		return click if click != "" else "—"
	var spelt := OS.get_keycode_string(key).to_upper()
	return "%s/%s" % [click, spelt] if click != "" else spelt


static func _fit(action: StringName, spec: Dictionary, instead := -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	InputMap.action_erase_events(action)
	var keys: Array = spec.get("keys", [])
	if instead == int(UNBOUND):
		keys = []
	elif instead > 0:
		keys = [instead]
	for key in keys:
		# Both spellings of the key: physical for real players on any layout, logical for
		# synthetic input in the checks. Referee For Fun learned this the hard way.
		var physical := InputEventKey.new()
		physical.physical_keycode = key as Key
		InputMap.action_add_event(action, physical)
		var logical := InputEventKey.new()
		logical.keycode = key as Key
		InputMap.action_add_event(action, logical)
	for button in spec.get("mouse", []):
		var click := InputEventMouseButton.new()
		click.button_index = button as MouseButton
		InputMap.action_add_event(action, click)
	for button in spec.get("buttons", []):
		var pad := InputEventJoypadButton.new()
		pad.button_index = button as JoyButton
		InputMap.action_add_event(action, pad)
	for axis in spec.get("axes", []):
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis[0] as JoyAxis
		motion.axis_value = axis[1]
		InputMap.action_add_event(action, motion)


static func reset(settings: Settings) -> void:
	settings.bindings.clear()
	settings.save()
	for action: StringName in DEFAULTS:
		_fit(action, DEFAULTS[action])
