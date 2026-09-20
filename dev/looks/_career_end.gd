extends Node

## What a finished career looks like.
##
##   Godot --path . --resolution 1600x900 res://dev/looks/_career_end.tscn
##
## Reaching the cup final used to end in two sentences. This fills a career in — four
## levels climbed, thirteen matches, the cards and the kilometres — and shows the page a
## referee is left with at the end of it.

var menu: Node
var t := 0.0
var shot := false


func _ready() -> void:
	var career := Career.new()
	career.fixture_seed = 7
	var seasons := [[8.4, 8.6, 8.5], [7.9, 8.0, 7.8], [8.5, 8.4, 8.6], [8.7, 8.8, 8.4], [8.9]]
	if OS.get_cmdline_user_args().has("midway"):
		seasons = [[8.4, 8.6, 8.5], [8.2]]
	for season in seasons:
		for mark: float in season:
			career.record({"home": 0, "away": 1}, mark, "%d–%d" % [randi() % 3, randi() % 3],
				{"distance_km": randf_range(9.0, 12.0), "card_list": ["yellow", "yellow", "red"]})
	Game.career = career
	menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)


func _process(delta: float) -> void:
	t += delta
	if t < 1.5 or shot:
		return
	menu._career()
	shot = true
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("res://dev/shots/career_%s.png"
		% ("midway" if OS.get_cmdline_user_args().has("midway") else "end"))
	get_tree().quit()
