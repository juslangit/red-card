extends Node

## Screenshots of the menu pages.
var menu: Node
var t := 0.0
var shots := ["main", "career", "quick", "training", "settings"]
var i := 0


func _ready() -> void:
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)


func _process(delta: float) -> void:
	t += delta
	if t < 2.0:
		return
	t = 0.0
	get_viewport().get_texture().get_image().save_png("res://dev/shots/menu_%s.png" % shots[i])
	i += 1
	if i >= shots.size():
		get_tree().quit()
		return
	match shots[i]:
		"career":
			menu._career()
		"quick":
			menu._quick_match()
		"training":
			menu._list("training")
		"settings":
			menu._settings()
