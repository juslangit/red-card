extends Node

## Frames of the title sequence as the menu opens.
var menu: Node
var t := 0.0
var shot := 0

func _ready() -> void:
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)

func _process(delta: float) -> void:
	t += delta
	if t > 0.5:
		t = 0.0
		get_viewport().get_texture().get_image().save_png("res://dev/shots/cut_title_%d.png" % shot)
		shot += 1
		if shot >= 20:
			get_tree().quit()
