extends Node3D

## A look at a ground with two teams lined up on it. Writes screenshots to dev/shots/.
##   Godot --path . res://dev/looks/_venue.tscn -- village

var shots := [
	{"name": "high", "pos": Vector3(-20, 28, -62), "look": Vector3(0, 0, 0)},
	{"name": "pitch", "pos": Vector3(-8, 1.7, -14), "look": Vector3(10, 1.0, 0)},
	{"name": "close", "pos": Vector3(-44, 1.6, -3), "look": Vector3(-46, 1.0, 1.5)},
	{"name": "crowd", "pos": Vector3(0, 1.7, -24), "look": Vector3(0, 1.0, -36)},
]
var level := "village"
var cam: Camera3D
var frame := 0
var shot := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		level = arg
	var venue := Venue.new()
	add_child(venue)
	venue.build(level)
	var home := Team.new()
	home.name = "Blueport"
	home.shirt = Color(0.12, 0.3, 0.8)
	home.shorts = Color(0.95, 0.95, 0.95)
	var away := Team.new()
	away.name = "Halcyon"
	away.index = 1
	away.attack = -1
	away.shirt = Color(0.85, 0.12, 0.12)
	away.shorts = Color(0.1, 0.1, 0.12)
	away.keeper_shirt = Color(0.95, 0.8, 0.1)
	venue.stands.set_colours(home.shirt, home.shorts, away.shirt, away.shorts)
	for team in [home, away]:
		for slot in Team.FORMATION_442:
			var p := Footballer.new()
			p.setup(team, slot.num, slot.role, "P%d" % slot.num)
			add_child(p)
			p.global_position = team.to_world(slot.u * 0.5, slot.v, venue.spec)
			p.heading = Vector3(team.attack, 0, 0)
			p.goal = p.global_position
	var ball := Ball.new()
	ball.spec = venue.spec
	add_child(ball)
	ball.place(Vector3(0, 0, 0))
	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	_aim()


func _aim() -> void:
	cam.global_position = shots[shot].pos
	cam.look_at(shots[shot].look, Vector3.UP)


func _process(_d: float) -> void:
	frame += 1
	for p in get_children():
		if p is Footballer:
			p.step(_d)
	if frame % 30 == 0:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://dev/shots/venue_%s_%s.png" % [level, shots[shot].name])
		shot += 1
		if shot >= shots.size():
			get_tree().quit()
			return
		_aim()
