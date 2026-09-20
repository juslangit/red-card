extends Node3D

## Showing a card: what you see, and what it looks like from outside.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_card.tscn
##
## Luqman could not see the card when he showed it on 2026-09-20. It was held twelve
## centimetres along the hand bone, which runs back down the forearm, so it sat behind his
## own fist. Two things have to be true at once now, and this shows both: the card is
## inside your own view — the print says how far it is from the middle of it, against a
## frame that reaches 39 degrees up and 55 across — and from outside it is a card in a
## raised hand rather than something floating near one.

var m: Match
var ref: Referee
var hud: Hud
var victim: Footballer
var watcher: Camera3D
var step := 0
var wait := 0.0
## Where the offender stands: up-sun of the referee, so the shot from outside is not
## looking straight into a blown-out sky.
var _to_him := Vector3(4.5, 0, -1.5)


func _ready() -> void:
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "town", 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(-6, 0, 6)
	ref.scripted = true
	m.attach_referee(ref)
	hud = Hud.new()
	hud.setup(m, ref, Game.settings)
	add_child(hud)
	watcher = Camera3D.new()
	watcher.fov = 32.0
	add_child(watcher)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://dev/shots/card_%s.png" % name)


## Puts the offender back in front of us and looks at him. Everybody walks to their places
## after a whistle, the man being booked along with them.
func _look_at_victim() -> void:
	victim.global_position = ref.global_position + _to_him
	victim.goal = victim.global_position
	var to := victim.global_position + Vector3(0, 1.5, 0) - ref.camera.global_position
	ref.yaw = atan2(-to.x, -to.z)
	ref.pitch = asin(to.normalized().y)


func _report() -> void:
	var cam := ref.camera
	var to_card := ref._card_node.global_position - cam.global_position
	var up := rad_to_deg(asin(clampf(to_card.normalized().dot(cam.global_transform.basis.y), -1.0, 1.0)))
	var across := rad_to_deg(asin(clampf(to_card.normalized().dot(cam.global_transform.basis.x), -1.0, 1.0)))
	print("card %.2f m from the eye, %.0f deg up and %.0f deg right of centre (the frame is 39 by 55)"
		% [to_card.length(), up, across])


func _process(delta: float) -> void:
	wait += delta
	match step:
		0:
			# A card can only be shown once play has started and then been stopped: whistle
			# the kick-off away, let it run, then whistle again.
			if wait > 1.0:
				m.whistle()
				step = 1
				wait = 0.0
		1:
			if m.phase == Match.Phase.LIVE and wait > 0.5:
				var sun := find_children("*", "DirectionalLight3D", true, false)
				if not sun.is_empty():
					var travel: Vector3 = -(sun[0] as DirectionalLight3D).global_transform.basis.z
					travel.y = 0.0
					if travel.length() > 0.01:
						_to_him = -travel.normalized() * 4.5
				victim = m.teams[1].players[5]
				m.ai.held[victim] = true
				_look_at_victim()
				m.whistle()
				step = 2
				wait = 0.0
		2:
			if wait > 0.8:
				_look_at_victim()
				ref.card(&"yellow")
				step = 3
				wait = 0.0
		3:
			if wait > 0.5:
				_shot("yellow_rising")
				step = 4
				wait = 0.0
		4:
			if wait > 0.6:
				_report()
				_shot("yellow_held")
				# From outside: close, a little above and to the side, with the pitch behind
				# him rather than the sky.
				var to_him := (victim.global_position - ref.global_position).normalized()
				watcher.global_position = ref.global_position + to_him.cross(Vector3.UP) * 1.9 \
					+ to_him * 1.2 + Vector3(0, 2.3, 0)
				watcher.look_at(ref._card_node.global_position)
				watcher.current = true
				step = 5
				wait = 0.0
		5:
			if wait > 0.25:
				_shot("yellow_from_outside")
				ref.camera.current = true
				step = 6
				wait = 0.0
		6:
			if wait > 1.6:
				_look_at_victim()
				ref.card(&"red")
				step = 7
				wait = 0.0
		7:
			if wait > 0.9:
				_report()
				_shot("red_held")
				get_tree().quit()
