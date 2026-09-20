extends Node

## Can the whole game be played from the keyboard?
##
##     Godot --headless --path . res://dev/checks/_controls.tscn
##
## Luqman played it on 2026-09-20 and asked for the game to be keyboard friendly rather
## than mouse-only. It was worse than it sounded: the whistle and the point were on the
## mouse buttons alone, and looking around — which the point depends on, since you give
## the restart you are looking at — could only be done with a mouse or a pad. A referee
## with no mouse could walk about and show cards and nothing else.
##
## So: every verb has a key, no two verbs share one, and the things a rebind must never
## break — the pause key, and the fact that the mouse still works — hold.

func _ready() -> void:
	var settings := Settings.new()
	Controls.ensure(settings)
	var bad := 0
	var claimed := {}
	for action: StringName in Controls.ORDER:
		var key := ""
		var click := ""
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var code: int = (event as InputEventKey).physical_keycode
				if code != 0:
					key = OS.get_keycode_string(code)
			elif event is InputEventMouseButton:
				click = "mouse"
		if key == "":
			bad += 1
			print("BAD  %s has no key at all" % action)
			continue
		if claimed.has(key):
			bad += 1
			print("BAD  %s and %s are both on %s" % [action, claimed[key], key])
		claimed[key] = action
		print("     %-16s %-8s %s" % [action, key, click])
	# The two that were mouse-only, and the ones that were nothing but a mouse.
	for action: StringName in [&"rc_whistle", &"rc_point"]:
		var has_click := false
		for event in InputMap.action_get_events(action):
			has_click = has_click or event is InputEventMouseButton
		if not has_click:
			bad += 1
			print("BAD  %s lost its mouse button — the keyboard is an addition, not a swap" % action)
	print("%d control problem(s)" % bad)
	get_tree().quit(1 if bad > 0 else 0)
