extends Node

## The foul flag from the referee's eyes: the "Behind your back" drill, with a screenshot
## while the flag is up behind the referee, and one after turning to face it.
var play: Node
var t := 0.0
var step := 0


func _ready() -> void:
	Game.pending = {"mode": "training", "scenario": "t_foul_flag", "level": "town", "home": 0, "away": 1, "half": 360.0}
	play = load("res://scenes/play.tscn").instantiate()
	add_child(play)


func _process(delta: float) -> void:
	t += delta
	var m: Match = play.m
	if step == 0 and not m.flag.is_empty():
		step = 1
		t = 0.0
	elif step == 1 and t > 0.4:
		get_viewport().get_texture().get_image().save_png("res://dev/shots/flag_behind.png")
		var ar = m.flag.assistant
		var to: Vector3 = ar.body.global_position - play.ref.global_position
		play.ref.yaw = atan2(-to.x, -to.z)
		play.ref.pitch = deg_to_rad(-3.0)
		step = 2
		t = 0.0
	elif step == 2 and t > 0.5:
		get_viewport().get_texture().get_image().save_png("res://dev/shots/flag_facing.png")
		get_tree().quit()
	elif t > 20.0:
		print("no flag")
		get_tree().quit()
