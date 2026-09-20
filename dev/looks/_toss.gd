extends Node3D

## The toss, before a ball is kicked.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_toss.tscn
##
## Law 8: the coin is tossed, the side that wins it chooses which goal to attack, and the
## other side kicks off. Added on 2026-09-20 — until then a match began with the players
## already lined up, and the handshake animation had been in the model since the clips
## were written with nowhere to happen.

var m: Match
var ref: Referee
var hud: Hud
var step := 0
var wait := 0.0


func _ready() -> void:
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "town", 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(0, 0, 6.5)
	ref.scripted = true
	m.attach_referee(ref)
	hud = Hud.new()
	hud.setup(m, ref, Game.settings)
	add_child(hud)
	m.begin_coin_toss()
	# Facing the middle, where the captains are coming to.
	var to := Vector3(0, 1.4, 0) - ref.camera.global_position
	ref.yaw = atan2(-to.x, -to.z)
	ref.pitch = asin(to.normalized().y)


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://dev/shots/toss_%s.png" % name)


func _process(delta: float) -> void:
	wait += delta
	match step:
		0:
			if wait > 5.0 and m.captains_ready():
				for c in m.captains:
					print("   %s #%d is %.1f m away, goal %.1f m off, state %d, can_move %s"
						% [c.team.short, c.number, c.global_position.distance_to(ref.global_position),
						c.global_position.distance_to(c.goal), c.state, c.can_move()])
				_shot("waiting")
				print("captains: %s" % ", ".join(m.captains.map(func(p): return "%s #%d" % [p.team.short, p.number])))
				print("phase before: %s" % Match.Phase.keys()[m.phase])
				m.toss_coin()
				step = 1
				wait = 0.0
		1:
			if wait > 0.5:
				_shot("shake")
				step = 2
				wait = 0.0
		2:
			if wait > 3.0:
				_shot("after")
				print("phase after: %s, %s kick off" % [Match.Phase.keys()[m.phase],
					m.kick_off_team.name if m.kick_off_team != null else "nobody"])
				get_tree().quit()
