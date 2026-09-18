class_name Stands
extends Node3D

## Everything around the pitch: rails, terraces, stands, roofs, floodlights, boards,
## dugouts, trees — and the people.
##
## The crowd is drawn with MultiMeshes, one per spectator model, so twelve thousand people
## cost two draw calls. Each model is merged once into a single mesh with its material
## colours baked into the vertices and its shirt marked for recolouring (see
## crowd.gdshader), which is what lets one man in an orange shirt become a ground full of
## people in their team's colours.
##
## Sides: the main stand is at -Z, where the dugouts and the fourth official are, as at
## nearly every ground. Home supporters fill the west end (-X) and the west half of the
## sides; away supporters take the east end.

const CROWD_MODELS := [
	{"path": "res://assets/sketchfab/simple_low_poly_character/simple_low_poly_character.glb",
		"height": 1.75, "shirt": ["Material.004"], "hair": "Material.002", "share": 0.55},
	{"path": "res://assets/sketchfab/low_poly_woman/low_poly_woman.glb",
		"height": 1.66, "shirt": ["blouse"], "hair": "hair", "share": 0.45},
]

## Drab clothes plus both teams' colours, filled in by `build` — palette slots 0-1 are
## the home side's shirt and shorts, 2-3 the away side's.
var palette: Array[Color] = [
	Color.RED, Color.WHITE, Color.BLUE, Color.WHITE,
	Color(0.3, 0.32, 0.36), Color(0.45, 0.42, 0.4), Color(0.2, 0.22, 0.26), Color(0.55, 0.5, 0.45),
]

## Somewhere to put the dugouts and technical areas for the match to find.
var dugout_home := Vector3.ZERO
var dugout_away := Vector3.ZERO
var fourth_official_spot := Vector3.ZERO
var big_screens: Array = []

var _level: Dictionary
var _spec: PitchSpec
var _crowd_material: ShaderMaterial
var _places: Array = []   # [{pos, facing, side}]
var _concrete: StandardMaterial3D
var _roof: StandardMaterial3D
var _seat_colour := Color(0.55, 0.12, 0.12)
var _rng := RandomNumberGenerator.new()


func build(level: Dictionary, spec: PitchSpec) -> void:
	_level = level
	_spec = spec
	_rng.seed = hash(level.id)
	_concrete = _mat(Color(0.52, 0.52, 0.54))
	_roof = _mat(Color(0.82, 0.83, 0.86))
	var hl := spec.half_length()
	var hw := spec.half_width()
	dugout_home = Vector3(-7.0, 0.0, -hw - 4.0)
	dugout_away = Vector3(7.0, 0.0, -hw - 4.0)
	fourth_official_spot = Vector3(0.0, 0.0, -hw - 3.0)

	match level.stands:
		"rail":
			_rail(hl + 3.0, hw + 2.5)
			_standing_line(Vector3(0, 0, -hw - 3.2), 80.0, Vector3(0, 0, 1), 2, 0.5)
			_standing_line(Vector3(0, 0, hw + 3.2), 60.0, Vector3(0, 0, -1), 1, 0.5)
			_trees(hl + 22.0, hw + 18.0, 70)
			_clubhouse(Vector3(-hl * 0.55, 0, -hw - 16.0))
		"one":
			_rail(hl + 3.0, hw + 2.5)
			_stand(Vector3(0, 0, -hw - 6.0), 64.0, Vector3(0, 0, 1), 10, true, 0.5)
			_standing_line(Vector3(0, 0, hw + 3.2), 90.0, Vector3(0, 0, -1), 2, 0.5)
			_standing_line(Vector3(-hl - 3.6, 0, 0), 40.0, Vector3(1, 0, 0), 2, 0.0)
			_standing_line(Vector3(hl + 3.6, 0, 0), 30.0, Vector3(-1, 0, 0), 2, 1.0)
			_trees(hl + 30.0, hw + 30.0, 50)
		"four":
			_boards(hl + 4.0, hw + 4.0)
			_stand(Vector3(0, 0, -hw - 8.0), spec.length + 8.0, Vector3(0, 0, 1), 18, true, 0.5)
			_stand(Vector3(0, 0, hw + 8.0), spec.length + 8.0, Vector3(0, 0, -1), 18, true, 0.5)
			_stand(Vector3(-hl - 9.0, 0, 0), spec.width, Vector3(1, 0, 0), 15, true, 0.0)
			_stand(Vector3(hl + 9.0, 0, 0), spec.width, Vector3(-1, 0, 0), 15, true, 1.0)
			_floodlight_towers(hl + 16.0, hw + 16.0)
		"bowl":
			_boards(hl + 4.0, hw + 4.0)
			for tier: int in [0, 1]:
				var back := 8.0 + tier * 17.0
				var lift := tier * 9.0
				_stand(Vector3(0, lift, -hw - back), spec.length + 14.0, Vector3(0, 0, 1), 18 - tier * 3, tier == 1, 0.5)
				_stand(Vector3(0, lift, hw + back), spec.length + 14.0, Vector3(0, 0, -1), 18 - tier * 3, tier == 1, 0.5)
				_stand(Vector3(-hl - back, lift, 0), spec.width + 14.0, Vector3(1, 0, 0), 16 - tier * 3, tier == 1, 0.0)
				_stand(Vector3(hl + back, lift, 0), spec.width + 14.0, Vector3(-1, 0, 0), 16 - tier * 3, tier == 1, 1.0)
			_roof_lights(hl + 34.0, hw + 34.0, 30.0)
			for end in [-1.0, 1.0]:
				_big_screen(Vector3((hl + 30.0) * end, 26.0, 18.0 * -end), Vector3(-end, 0, 0))
	_dugouts()
	_fill_crowd()


func set_colours(home_shirt: Color, home_shorts: Color, away_shirt: Color, away_shorts: Color) -> void:
	palette[0] = home_shirt
	palette[1] = home_shorts
	palette[2] = away_shirt
	palette[3] = away_shorts
	if _crowd_material != null:
		_crowd_material.set_shader_parameter("palette", palette)


## 0 to 1 for each set of supporters. The match eases these about.
func set_excitement(home: float, away: float) -> void:
	if _crowd_material != null:
		_crowd_material.set_shader_parameter("excite_home", home)
		_crowd_material.set_shader_parameter("excite_away", away)


# --- structures -------------------------------------------------------------------------

func _mat(colour: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = emission
	return m


func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node


## A post-and-rail fence around the pitch, the way every recreation ground has one.
func _rail(x: float, z: float) -> void:
	var white := _mat(Color(0.92, 0.92, 0.9))
	var height := 1.05
	for side in [-1.0, 1.0]:
		_box(Vector3(x * 2.0, 0.06, 0.06), Vector3(0, height, z * side), white)
		_box(Vector3(0.06, 0.06, z * 2.0), Vector3(x * side, height, 0), white)
		var posts := int(x * 2.0 / 3.0)
		for i in posts + 1:
			var px := -x + i * (x * 2.0 / posts)
			_box(Vector3(0.07, height, 0.07), Vector3(px, height * 0.5, z * side), white)
		var end_posts := int(z * 2.0 / 3.0)
		for i in end_posts + 1:
			var pz := -z + i * (z * 2.0 / end_posts)
			_box(Vector3(0.07, height, 0.07), Vector3(x * side, height * 0.5, pz), white)


## Advertising boards: a ring of lit panels with sponsors on, for the stadium grounds.
## The sponsors are the fictional brands Referee For Fun invented.
func _boards(x: float, z: float) -> void:
	var sponsors := ["BLUEPORT", "HALCYON", "MERIDIAN", "AXIS SPORT", "NORTHGATE", "KESTREL", "RED CARD"]
	var colours := [Color(0.1, 0.3, 0.75), Color(0.08, 0.5, 0.45), Color(0.7, 0.35, 0.1),
		Color(0.15, 0.15, 0.18), Color(0.6, 0.1, 0.12), Color(0.35, 0.2, 0.6), Color(0.75, 0.08, 0.1)]
	var font: Font = load("res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf")
	var panel := 8.0
	var runs := [
		{"from": Vector3(-x, 0, -z), "to": Vector3(x, 0, -z), "face": Vector3(0, 0, 1)},
		{"from": Vector3(-x, 0, z), "to": Vector3(x, 0, z), "face": Vector3(0, 0, -1)},
		{"from": Vector3(-x, 0, -z), "to": Vector3(-x, 0, z), "face": Vector3(1, 0, 0)},
		{"from": Vector3(x, 0, -z), "to": Vector3(x, 0, z), "face": Vector3(-1, 0, 0)},
	]
	var n := 0
	for run in runs:
		var span: Vector3 = run.to - run.from
		var count := int(span.length() / panel)
		for i in count:
			var at: Vector3 = run.from + span * ((i + 0.5) / count)
			# Leave a gap behind each goal, where the photographers and the net are.
			if absf(at.z) < 6.0 and absf(at.x) > x - 1.0:
				continue
			var colour: Color = colours[n % colours.size()]
			var board := _box(Vector3(panel - 0.2, 0.9, 0.12) if absf(run.face.z) > 0.5 else Vector3(0.12, 0.9, panel - 0.2),
				at + Vector3(0, 0.45, 0), _mat(colour, 0.6))
			var label := Label3D.new()
			label.text = sponsors[n % sponsors.size()]
			label.font = font
			label.font_size = 96
			label.pixel_size = 0.006
			label.modulate = Color.WHITE
			label.shaded = false
			label.position = at + Vector3(0, 0.45, 0) + (run.face as Vector3) * 0.07
			label.basis = Basis.looking_at(-(run.face as Vector3), Vector3.UP)
			add_child(label)
			n += 1


## A terrace or a seated stand: rows of steps rising away from the pitch, facing it.
## `side` says whose supporters sit there (0 home, 1 away, 0.5 mixed along its length).
func _stand(front: Vector3, span: float, facing: Vector3, rows: int, roofed: bool, side: float) -> void:
	var across := Vector3.UP.cross(facing).normalized()
	var depth := 0.8
	var rise := 0.42
	var stand := Node3D.new()
	add_child(stand)
	for r in rows:
		var back := -facing * (r * depth + depth * 0.5)
		var top := front.y + (r + 1) * rise
		var centre := front + back
		centre.y = top * 0.5
		var size := Vector3(span, top, depth) if absf(facing.z) > 0.5 else Vector3(depth, top, span)
		_box(size, centre, _concrete, stand)
		# People along the row, a seat's width apart, with gaps for the aisles.
		var seats := int(span / 0.62)
		for s in seats:
			var t := (s + 0.5) / seats - 0.5
			if absf(fposmod(t * span, 14.0) - 7.0) < 0.6:
				continue
			var pos := front + back + across * (t * span)
			pos.y = top
			var who := side
			if side == 0.5:
				who = 0.0 if t < 0.0 else 1.0
			_places.append({"pos": pos, "facing": facing, "side": who})
	# Back wall and roof.
	var height := front.y + rows * rise
	var back_centre := front - facing * (rows * depth + 0.15)
	back_centre.y = (height + 4.0) * 0.5
	_box(Vector3(span, height + 4.0, 0.3) if absf(facing.z) > 0.5 else Vector3(0.3, height + 4.0, span),
		back_centre, _concrete, stand)
	if roofed:
		var roof_centre := front - facing * (rows * depth * 0.5)
		roof_centre.y = height + 4.2
		var roof_size := Vector3(span, 0.25, rows * depth + 2.0) if absf(facing.z) > 0.5 \
			else Vector3(rows * depth + 2.0, 0.25, span)
		_box(roof_size, roof_centre, _roof, stand)
		# Pillars along the front of the roof, for the smaller grounds.
		if _level.stands == "one":
			for i in 7:
				var p := front + across * ((i / 6.0 - 0.5) * span) + facing * 0.2
				p.y = (height + 4.2) * 0.5
				_box(Vector3(0.2, height + 4.2, 0.2), p, _roof, stand)


## A line of people standing behind the rail, `rows` deep.
func _standing_line(centre: Vector3, span: float, facing: Vector3, rows: int, side: float) -> void:
	var across := Vector3.UP.cross(facing).normalized()
	var people := int(_level.crowd * span / 200.0)
	for i in people:
		var t := _rng.randf_range(-0.5, 0.5)
		var r := _rng.randi_range(0, rows - 1)
		var pos := centre + across * (t * span) - facing * (r * 0.7 + _rng.randf() * 0.3)
		pos.y = 0.0
		var who := side
		if side == 0.5:
			who = 0.0 if t < 0.0 else 1.0
		_places.append({"pos": pos, "facing": facing, "side": who, "standing": true})


func _trees(x: float, z: float, count: int) -> void:
	var trunk := _mat(Color(0.3, 0.22, 0.15))
	var leaves := _mat(Color(0.18, 0.32, 0.14))
	for i in count:
		var angle := _rng.randf() * TAU
		var pos := Vector3(cos(angle) * x, 0, sin(angle) * z) * _rng.randf_range(1.0, 1.35)
		var h := _rng.randf_range(7.0, 13.0)
		_box(Vector3(0.5, h * 0.5, 0.5), pos + Vector3(0, h * 0.25, 0), trunk)
		var crown := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = h * 0.32
		sphere.height = h * 0.55
		sphere.radial_segments = 10
		sphere.rings = 6
		crown.mesh = sphere
		crown.material_override = leaves
		crown.position = pos + Vector3(0, h * 0.68, 0)
		add_child(crown)


func _clubhouse(at: Vector3) -> void:
	_box(Vector3(16, 4, 7), at + Vector3(0, 2, 0), _mat(Color(0.75, 0.68, 0.55)))
	_box(Vector3(17, 0.3, 8), at + Vector3(0, 4.15, 0), _mat(Color(0.35, 0.18, 0.14)))
	var sign := Label3D.new()
	sign.text = _level.name.to_upper()
	sign.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	sign.font_size = 96
	sign.pixel_size = 0.01
	sign.position = at + Vector3(0, 3.3, 3.55)
	sign.modulate = Color(0.95, 0.95, 0.9)
	add_child(sign)


func _floodlight_towers(x: float, z: float) -> void:
	var steel := _mat(Color(0.6, 0.62, 0.65))
	var lamp := _mat(Color(1.0, 0.98, 0.9), 6.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(x * sx, 0, z * sz)
			_box(Vector3(0.9, 38, 0.9), base + Vector3(0, 19, 0), steel)
			var head := _box(Vector3(6, 3.5, 0.4), base + Vector3(0, 38.5, 0), lamp)
			head.look_at(Vector3(0, 0, 0), Vector3.UP)


func _roof_lights(x: float, z: float, height: float) -> void:
	var lamp := _mat(Color(1.0, 0.98, 0.92), 5.0)
	for side in [-1.0, 1.0]:
		_box(Vector3(x * 1.7, 0.6, 0.6), Vector3(0, height, z * side), lamp)
		_box(Vector3(0.6, 0.6, z * 1.5), Vector3(x * side, height, 0), lamp)


func _big_screen(at: Vector3, facing: Vector3) -> void:
	var frame := _box(Vector3(0.5, 7.5, 13.0), at, _mat(Color(0.05, 0.05, 0.06)))
	var screen := Label3D.new()
	screen.text = ""
	screen.font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	screen.font_size = 220
	screen.pixel_size = 0.018
	screen.modulate = Color(1.0, 0.95, 0.8)
	screen.shaded = false
	screen.position = at + facing * 0.3
	screen.basis = Basis.looking_at(-facing, Vector3.UP)
	add_child(screen)
	big_screens.append(screen)
	frame.name = "BigScreen"


func _dugouts() -> void:
	var shell := _mat(Color(0.2, 0.22, 0.26))
	var glass := _mat(Color(0.6, 0.7, 0.8, 0.35))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for at in [dugout_home, dugout_away]:
		var root := Node3D.new()
		root.position = at + Vector3(0, 0, -1.5)
		add_child(root)
		_box(Vector3(6, 0.1, 2.2), Vector3(0, 2.3, 0), shell, root)
		_box(Vector3(6, 2.3, 0.1), Vector3(0, 1.15, -1.1), shell, root)
		_box(Vector3(0.1, 2.3, 2.2), Vector3(-3, 1.15, 0), glass, root)
		_box(Vector3(0.1, 2.3, 2.2), Vector3(3, 1.15, 0), glass, root)
		_box(Vector3(5.6, 0.45, 0.6), Vector3(0, 0.22, -0.6), _mat(Color(0.5, 0.1, 0.1)), root)
	# The technical areas: a dashed box painted in front of each dugout would be ideal;
	# a pair of white markers stands in for it.


# --- the crowd --------------------------------------------------------------------------

func _fill_crowd() -> void:
	var wanted: int = _level.crowd
	if _places.is_empty():
		return
	# Thin the available places down to the size of the crowd, keeping the front rows
	# fuller than the back — the way a ground fills.
	_places.shuffle()
	var chosen := _places.slice(0, mini(wanted, _places.size()))

	_crowd_material = ShaderMaterial.new()
	_crowd_material.shader = load("res://assets/shaders/crowd.gdshader")
	_crowd_material.set_shader_parameter("palette", palette)

	var split := [[], []]
	for p in chosen:
		split[0 if _rng.randf() < CROWD_MODELS[0].share else 1].append(p)
	for m in CROWD_MODELS.size():
		var mesh := _merged_person(CROWD_MODELS[m])
		if mesh == null or split[m].is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = split[m].size()
		for i in split[m].size():
			var p: Dictionary = split[m][i]
			var basis := Basis.looking_at(-(p.facing as Vector3), Vector3.UP)
			basis = basis.scaled(Vector3.ONE * _rng.randf_range(0.93, 1.06))
			multi.set_instance_transform(i, Transform3D(basis, p.pos))
			# Shirt: most wear their side's colours, the rest wear whatever they own.
			var index := _rng.randi_range(4, 7)
			if _rng.randf() < 0.55:
				index = 0 if p.side < 0.5 else 2
			elif _rng.randf() < 0.25:
				index = 1 if p.side < 0.5 else 3
			multi.set_instance_custom_data(i, Color(_rng.randf(), p.side, index, 0.0))
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = _crowd_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)


## One spectator model, flattened into a single mesh at a given height, with every
## material's colour baked into the vertex colours and the shirt marked with alpha 0.
##
## The node transforms in these files cannot be trusted to stand the person up: the
## woman's vertices are stored in her skin's bind space, so her own transforms lay her
## on her back at four times life size (the first render of the village ground had
## giants lying along the rail). So the merged vertices are measured instead — a person
## is taller than they are wide or deep, so the longest side of the box is up, and the
## end nearer the hair is the top.
func _merged_person(model: Dictionary) -> ArrayMesh:
	var scene: PackedScene = load(model.path)
	if scene == null:
		return null
	var root := scene.instantiate()
	var verts_all: Array[Vector3] = []
	var normals_all: Array[Vector3] = []
	var colours_all: Array[Color] = []
	var hair_sum := Vector3.ZERO
	var hair_count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var xform := Transform3D()
		var walk: Node = node
		while walk != root:
			xform = (walk as Node3D).transform * xform
			walk = walk.get_parent()
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var material := mesh.surface_get_material(s)
			var colour := Color(0.6, 0.6, 0.6)
			var is_shirt := false
			var is_hair := false
			if material is BaseMaterial3D:
				colour = (material as BaseMaterial3D).albedo_color
				is_shirt = material.resource_name in model.shirt
				is_hair = material.resource_name == model.hair
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var order: Array = []
			if indices != null and (indices as PackedInt32Array).size() > 0:
				order = Array(indices)
			else:
				order = range(verts.size())
			for i in order:
				var v: Vector3 = xform * verts[i]
				verts_all.append(v)
				normals_all.append((xform.basis * normals[i]).normalized() if normals.size() > i else Vector3.UP)
				colours_all.append(Color(colour.r, colour.g, colour.b, 0.0 if is_shirt else 1.0))
				if is_hair:
					hair_sum += v
					hair_count += 1
	root.free()
	if verts_all.is_empty():
		return null
	var box := AABB(verts_all[0], Vector3.ZERO)
	for v in verts_all:
		box = box.expand(v)
	var up_axis := box.size.max_axis_index()
	var centre := box.get_center()
	var up := Vector3.ZERO
	up[up_axis] = 1.0
	if hair_count > 0 and (hair_sum / hair_count)[up_axis] < centre[up_axis]:
		up = -up
	# Turn `up` onto +Y.
	var turn := Basis(Quaternion(up, Vector3.UP)) if up.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	var height := box.size[up_axis]
	var scale: float = model.height / maxf(height, 0.001)
	var lowest := INF
	for v in verts_all:
		lowest = minf(lowest, (turn * (v - centre)).y)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts_all.size():
		var v := turn * (verts_all[i] - centre)
		v.y -= lowest
		tool.set_color(colours_all[i])
		tool.set_normal(turn * normals_all[i])
		tool.add_vertex(v * scale)
	return tool.commit()
