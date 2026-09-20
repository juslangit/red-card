extends Node

## Can the menus be driven from the keyboard alone?
##
##     Godot --headless --path . res://dev/checks/_menu_keys.tscn
##
## Luqman asked on 2026-09-20 for the selection buttons — the ground, the clubs, the length
## of a half — to step with the left and right arrows instead of only going forwards one
## press at a time. This walks the quick-match page with nothing but key presses: right to
## step a setting on, left to step it back, and it checks that the focus stays on the thing
## being changed rather than jumping to the top of a rebuilt page.

var menu: Node
var bad := 0
var step := 0
var _wait := 0.0
var _before := ""


func _ready() -> void:
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)


func _chooser(starts_with: String) -> Button:
	for child in menu._page.get_children():
		if child is Button and (child as Button).text.contains(starts_with):
			return child
	return null


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _process(delta: float) -> void:
	_wait += delta
	if _wait < 0.25:
		return
	_wait = 0.0
	match step:
		0:
			menu._quick_match()
		1:
			var ground := _chooser("Ground")
			if ground == null:
				print("BAD  no ground chooser on the quick match page")
				bad += 1
				step = 90
				return
			ground.grab_focus()
			_before = ground.text
			_press(&"ui_right")
		2:
			var ground := _chooser("Ground")
			if ground == null or ground.text == _before:
				print("BAD  right arrow did not change the ground (still %s)" % _before)
				bad += 1
			else:
				print("     right: %s → %s" % [_before.strip_edges(), ground.text.strip_edges()])
			# The focus must have followed the page rebuild, or the next arrow press would
			# land on whatever the page grabbed focus for instead.
			if ground != null and not ground.has_focus():
				print("BAD  the focus left the ground chooser when the page was rebuilt")
				bad += 1
			_before = ground.text if ground != null else ""
			_press(&"ui_left")
		3:
			var ground := _chooser("Ground")
			if ground == null or ground.text == _before:
				print("BAD  left arrow did not change the ground (still %s)" % _before)
				bad += 1
			else:
				print("     left:  %s → %s" % [_before.strip_edges(), ground.text.strip_edges()])
			# And the halves, which is the one that is not a list of places.
			var halves := _chooser("Halves")
			if halves == null:
				print("BAD  no halves chooser")
				bad += 1
			else:
				halves.grab_focus()
				_before = halves.text
				_press(&"ui_left")
		4:
			var halves := _chooser("Halves")
			if halves == null or halves.text == _before:
				print("BAD  left arrow did not change the half length (still %s)" % _before)
				bad += 1
			else:
				print("     left:  %s → %s" % [_before.strip_edges(), halves.text.strip_edges()])
			# Wiping a career takes two presses. It used to take one, from a button sitting
			# directly under "Referee this match" and looking exactly like it.
			menu._career()
			step = 40
			return
		40:
			var reset := _chooser("Start a new career")
			if reset == null:
				print("BAD  no reset button on the career page")
				bad += 1
			else:
				reset.emit_signal("pressed")
			step = 41
			return
		41:
			if _chooser("Start a new career") != null:
				print("BAD  one press of the reset button did not ask for a second")
				bad += 1
			elif _chooser("Yes — wipe it") == null:
				print("BAD  the reset button did not turn into a confirmation")
				bad += 1
			else:
				print("     wiping a career asks first")
			step = 89
		_:
			print("%d menu key problem(s)" % bad)
			get_tree().quit(1 if bad > 0 else 0)
			return
	step += 1
