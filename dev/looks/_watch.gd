extends Node3D

## Watches a bot-refereed match from a broadcast camera and saves a picture every couple
## of seconds, to see what the football looks like rather than only count it.
##   Godot --path . res://dev/looks/_watch.tscn -- town 12

var m: Match
var cam: Camera3D
var shots := 12
var taken := 0
var next := 6.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var level := args[0] if args.size() > 0 else "town"
	shots = int(args[1]) if args.size() > 1 else 12
	var settings := Settings.new()
	settings.apply()
	m = Match.new()
	m.setup(Names.team_from(0), Names.team_from(1), level, 360.0)
	add_child(m)
	var ref := Referee.new()
	ref.setup(m, settings)
	add_child(ref)
	ref.global_position = Vector3(-5, 0, 10)
	m.attach_referee(ref)
	var bot := BotReferee.new()
	bot.setup(m, ref)
	add_child(bot)
	cam = Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	var b := m.ball.global_position
	cam.global_position = Vector3(clampf(b.x, -35, 35) * 0.9, 34, -m.spec.half_width() - 30)
	cam.look_at(Vector3(clampf(b.x, -40, 40), 0, 0), Vector3.UP)
	if m.clock > next:
		next += 2.5
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://dev/shots/watch_%02d.png" % taken)
		taken += 1
		if taken >= shots:
			get_tree().quit()
