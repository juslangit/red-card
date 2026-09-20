extends Node

## The pause screen over a training drill, as a screenshot.
var play: Node
var t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.pending = {"mode": "training", "scenario": "t_move", "level": "town", "home": 0, "away": 1, "half": 360.0}
	play = load("res://scenes/play.tscn").instantiate()
	add_child(play)


func _process(delta: float) -> void:
	t += delta
	if t > 1.5 and not play.pause_menu.visible:
		play.pause_menu.toggle()
	if t > 2.5:
		get_viewport().get_texture().get_image().save_png("res://dev/shots/pause.png")
		get_tree().quit()
