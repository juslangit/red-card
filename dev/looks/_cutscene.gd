extends Node3D

## The cutscenes, filmed frame by frame.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_cutscene.tscn [-- walkout|goal|red|ceremony]
##
## Plays a scene over a real match and saves a frame every third of a second, so the camera
## moves can be looked at as a strip of stills rather than described. Written for the
## cutscenes added on 2026-09-21.

var m: Match
var ref: Referee
var scene: Cutscene
var which := "walkout"
var shot := 0
var wait := 0.0
var started := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	which = args[0] if args.size() > 0 else "walkout"
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), "final" if which == "ceremony" else "town", 360.0)
	add_child(m)
	ref = Referee.new()
	ref.setup(m, Game.settings)
	add_child(ref)
	ref.global_position = Vector3(-4, 0, 12)
	ref.scripted = true
	m.attach_referee(ref)
	var hud := Hud.new()
	hud.setup(m, ref, Game.settings)
	add_child(hud)
	scene = Cutscene.new(m)
	scene.hud = hud
	scene.referee = ref
	add_child(scene)


func _process(delta: float) -> void:
	if not started:
		started = true
		_start()
		return
	wait += delta
	if wait > 0.33 and scene.playing():
		wait = 0.0
		get_viewport().get_texture().get_image().save_png("res://dev/shots/cut_%s_%d.png" % [which, shot])
		shot += 1
	elif not scene.playing() and shot > 0:
		print("%s: %d frames" % [which, shot])
		get_tree().quit()


func _start() -> void:
	match which:
		"walkout":
			var line := -m.spec.half_width() - 1.5
			for i in m.players.size():
				var p: Footballer = m.players[i]
				p.goal = p.global_position
				p.global_position = Vector3(-38.0 + i * 3.4, 0.0, line)
				p.hurry = 0.35
				p.face_point = Vector3(p.goal.x, 0.0, p.goal.z)
			ref.global_position = Vector3(-2.0, 0.0, line - 1.0)
			m.walking_out = true
			scene.play(Cutscenes.walkout(m, ref), func(): m.walking_out = false, false)
		"goal":
			var scorer: Footballer = m.teams[0].players[9]
			scorer.global_position = Vector3(34, 0, 6)
			scorer.celebrate(3.0)
			scene.play(Cutscenes.goal(m, scorer))
		"red":
			var off: Footballer = m.teams[1].players[5]
			off.global_position = Vector3(-6, 0, 4)
			scene.play(Cutscenes.red_card(m, off))
		"ceremony":
			ref.global_position = Vector3(0, 0, 6)
			scene.play(Cutscenes.ceremony(m, ref))
		_:
			scene.play(Cutscenes.title(m.spec))
