class_name Hud
extends CanvasLayer

## What the referee sees on top of the world.
##
## Very little, on purpose. Referee For Fun's rule holds here: nothing on screen during
## play may give the truth away. There is no "that was a foul" and no suspicious pause —
## only what a referee on the field actually has: the score, what their pointing arm
## currently means, who they are looking at when they are about to book somebody, an
## assistant's flag when one goes up, and their watch.
##
## Big and themed like a broadcast, as Luqman asked of Referee For Fun (2026-09-08):
## everything here is sized from UiTheme so "bigger" is one edit.

var m: Match
var ref: Referee
var settings: Settings

var _root: Control
var _crosshair: Control
var _prompt: Label
var _prompt_plate: PanelContainer
var _target: Label
var _target_plate: PanelContainer
var _hint: Label
var _hint_plate: PanelContainer
var _flag: PanelContainer
var _flag_label: Label
var _flag_marker: Label
var _flag_edge: Label
var _score_home: Label
var _score_away: Label
var _half_label: Label
var _stamina: ProgressBar
var _watch: PanelContainer
var _watch_label: Label
var _notebook: PanelContainer
var _notebook_label: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _message: PanelContainer
var _message_label: Label
var _message_left := 0.0
var _notes: Array[String] = []


func setup(match_node: Match, referee: Referee, player_settings: Settings) -> void:
	m = match_node
	ref = referee
	settings = player_settings


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)
	_build_crosshair()
	_build_score_bug()
	_build_prompts()
	_build_watch()
	_build_notebook()
	_build_stamina()
	m.decision_made.connect(_on_decision)
	m.message.connect(func(text, seconds): _show_message(text, seconds))
	m.card_shown.connect(_on_card)
	m.scored.connect(_on_goal)


func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(func():
		_crosshair.draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.85))
		_crosshair.draw_arc(Vector2.ZERO, 9.0, 0, TAU, 24, Color(0, 0, 0, 0.35), 2.0))
	_root.add_child(_crosshair)


## Broadcast score bug, top left: two slanted colour blocks and the score.
func _build_score_bug() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(40, 34)
	bar.add_theme_constant_override("separation", 0)
	_root.add_child(bar)
	var home := m.teams[0]
	var away := m.teams[1]
	bar.add_child(_team_block(home))
	var score := PanelContainer.new()
	score.add_theme_stylebox_override("panel", UiTheme.slant(UiTheme.INK))
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 18)
	_score_home = UiTheme.label("0", UiTheme.TITLE, UiTheme.CHALK, UiTheme.display())
	_score_away = UiTheme.label("0", UiTheme.TITLE, UiTheme.CHALK, UiTheme.display())
	score_row.add_child(_score_home)
	score_row.add_child(UiTheme.label("–", UiTheme.HEADING, UiTheme.MUTED, UiTheme.heavy()))
	score_row.add_child(_score_away)
	score.add_child(score_row)
	bar.add_child(score)
	bar.add_child(_team_block(away))
	var half := PanelContainer.new()
	half.add_theme_stylebox_override("panel", UiTheme.slant(UiTheme.ACCENT))
	_half_label = UiTheme.label("1ST HALF", UiTheme.SMALL, UiTheme.INK, UiTheme.heavy())
	half.add_child(_half_label)
	bar.add_child(half)


func _team_block(team: Team) -> PanelContainer:
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", UiTheme.slant(team.shirt.darkened(0.1)))
	var text := team.short
	var ink := UiTheme.CHALK if team.shirt.get_luminance() < 0.6 else UiTheme.INK
	block.add_child(UiTheme.label(text, UiTheme.HEADING, ink, UiTheme.heavy()))
	block.custom_minimum_size = Vector2(120, 0)
	return block


func _plate(edge: Color, label_size: int) -> Array:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UiTheme.plate(edge, 0.82))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UiTheme.label("", label_size, UiTheme.CHALK, UiTheme.heavy())
	plate.add_child(label)
	_root.add_child(plate)
	plate.visible = false
	return [plate, label]


func _build_prompts() -> void:
	var p := _plate(UiTheme.ACCENT, UiTheme.HEADING)
	_prompt_plate = p[0]
	_prompt = p[1]
	var t := _plate(UiTheme.YELLOW, UiTheme.BODY)
	_target_plate = t[0]
	_target = t[1]
	var h := _plate(UiTheme.EDGE, UiTheme.BODY)
	_hint_plate = h[0]
	_hint = h[1]
	var f := _plate(UiTheme.YELLOW, UiTheme.HEADING)
	_flag = f[0]
	_flag_label = f[1]
	_flag_marker = UiTheme.label("⚑", 64, UiTheme.YELLOW, UiTheme.heavy())
	_flag_marker.add_theme_constant_override("outline_size", 10)
	_flag_marker.add_theme_color_override("font_outline_color", UiTheme.INK)
	_flag_marker.visible = false
	_root.add_child(_flag_marker)
	_flag_edge = UiTheme.label("", UiTheme.TITLE, UiTheme.YELLOW, UiTheme.display())
	_flag_edge.add_theme_constant_override("outline_size", 12)
	_flag_edge.add_theme_color_override("font_outline_color", UiTheme.INK)
	_flag_edge.visible = false
	_root.add_child(_flag_edge)
	var toast := _plate(UiTheme.ACCENT, UiTheme.TITLE)
	_toast = toast[0]
	_toast_label = toast[1]
	_toast_label.add_theme_font_override("font", UiTheme.display())
	var msg := _plate(UiTheme.BLUE, UiTheme.BODY)
	_message = msg[0]
	_message_label = msg[1]


func _build_watch() -> void:
	_watch = PanelContainer.new()
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.03, 0.04, 0.04, 0.92)
	face.set_corner_radius_all(26)
	face.set_border_width_all(8)
	face.border_color = Color(0.2, 0.22, 0.24)
	face.set_content_margin_all(26)
	_watch.add_theme_stylebox_override("panel", face)
	var box := VBoxContainer.new()
	_watch_label = UiTheme.label("00:00", 96, Color(0.7, 1.0, 0.78), UiTheme.display())
	box.add_child(_watch_label)
	_watch.add_child(box)
	_watch.visible = false
	_root.add_child(_watch)


func _build_notebook() -> void:
	_notebook = PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(0.96, 0.94, 0.86, 0.97)
	paper.set_content_margin_all(36)
	paper.border_width_top = 10
	paper.border_color = UiTheme.RED
	_notebook.add_theme_stylebox_override("panel", paper)
	_notebook_label = UiTheme.label("", UiTheme.BODY, Color(0.12, 0.12, 0.2), UiTheme.strong())
	_notebook_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_notebook.add_child(_notebook_label)
	_notebook.visible = false
	_root.add_child(_notebook)


func _build_stamina() -> void:
	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	_stamina.max_value = 1.0
	_stamina.custom_minimum_size = Vector2(260, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.9, 0.6, 0.85)
	_stamina.add_theme_stylebox_override("background", bg)
	_stamina.add_theme_stylebox_override("fill", fill)
	_root.add_child(_stamina)


func _process(delta: float) -> void:
	if m == null or ref == null:
		return
	var size := _root.get_viewport_rect().size
	var centre := size * 0.5
	_crosshair.position = centre
	_score_home.text = str(m.teams[0].goals)
	_score_away.text = str(m.teams[1].goals)
	_half_label.text = "1ST HALF" if m.half == 1 else "2ND HALF"

	# What pointing would give.
	var meaning := ref.interpret_point()
	_prompt_plate.visible = not meaning.is_empty()
	if _prompt_plate.visible:
		var key := Controls.short(settings, &"rc_point")
		_prompt.text = ("%s   %s" % [key, meaning.label]) if meaning.has("type") else meaning.label
		_place(_prompt_plate, centre + Vector2(0, 70), true)

	# Who you are looking at, when you might book them.
	var target: Footballer = null
	if m.phase in [Match.Phase.STOPPED, Match.Phase.SET_PIECE, Match.Phase.GOAL]:
		target = ref.target_player()
	_target_plate.visible = target != null
	if target != null:
		var booked := "  (booked)" if target.yellow_cards > 0 else ""
		_target.text = "%s #%d %s%s    %s yellow · %s red" % [target.team.short, target.number,
			target.player_name.split(" ")[-1].to_upper(), booked,
			Controls.short(settings, &"rc_yellow"), Controls.short(settings, &"rc_red")]
		_place(_target_plate, centre + Vector2(0, -110), true)

	# The one line that says what the moment needs from you.
	var hint := _hint_text()
	_hint_plate.visible = hint != ""
	if _hint_plate.visible:
		_hint.text = hint
		_place(_hint_plate, Vector2(centre.x, size.y - 90), true)

	# An assistant's flag.
	_flag.visible = not m.flag.is_empty()
	if _flag.visible:
		var what := "OFFSIDE" if m.flag.has("offside") else "FOUL"
		var extra := ("  ·  %s advantage" % Controls.short(settings, &"rc_advantage")) if what == "FOUL" else ""
		_flag_label.text = "⚑  %s FLAG — %s whistle · %s wave down%s" % [what,
			Controls.short(settings, &"rc_whistle"), Controls.short(settings, &"rc_wave"), extra]
		# On the top row beside the score bug, clear of a drill's brief below it.
		_flag.reset_size()
		var w := _flag.get_combined_minimum_size().x
		_place(_flag, Vector2(maxf(centre.x, 470.0 + w * 0.5), 62), true)
	_point_at_flag(size)

	# The watch.
	_watch.visible = ref.holding_watch
	if _watch.visible:
		var secs := m.match_seconds()
		_watch_label.text = "%02d:%02d" % [int(secs / 60.0), int(fmod(secs, 60.0))]
		_place(_watch, Vector2(centre.x, size.y - 260), true)

	_notebook.visible = Input.is_action_pressed(&"rc_notebook") or _notebook.has_meta("open")
	if _notebook.visible:
		_notebook_label.text = "NOTEBOOK\n\n" + ("\n".join(_notes) if not _notes.is_empty() else "Nothing written yet.")
		_place(_notebook, Vector2(size.x - 380, size.y * 0.5), true)

	_stamina.value = ref.stamina
	_stamina.position = Vector2(40, size.y - 60)
	_stamina.modulate.a = 0.35 if ref.stamina > 0.95 else 1.0

	_toast_left -= delta
	_toast.visible = _toast_left > 0.0
	if _toast.visible:
		_place(_toast, Vector2(centre.x, size.y * 0.28), true)
	_message_left -= delta
	_message.visible = _message_left > 0.0
	if _message.visible:
		_place(_message, Vector2(centre.x, 220), true)


## Where the assistant with his flag up is. On screen: a flag marker over his head, because
## at thirty-five metres a real flag is a few pixels. Off screen: a big arrow at the edge of
## the screen on the side to turn to — Luqman asked for the linesmen to help the referee
## see what he cannot, and a flag behind your back helps nobody.
func _point_at_flag(size: Vector2) -> void:
	var ar = m.flag.get("assistant") if not m.flag.is_empty() else null
	if ar == null:
		_flag_marker.visible = false
		_flag_edge.visible = false
		return
	var head: Vector3 = ar.body.global_position + Vector3(0, 2.6, 0)
	var cam := ref.camera
	var on_screen := false
	if not cam.is_position_behind(head):
		var at := cam.unproject_position(head)
		if at.x > 40 and at.x < size.x - 40 and at.y > 40 and at.y < size.y - 40:
			on_screen = true
			_flag_marker.visible = true
			_flag_marker.reset_size()
			_flag_marker.position = at - _flag_marker.size * 0.5
	_flag_marker.visible = on_screen
	_flag_edge.visible = not on_screen
	if not on_screen:
		var to: Vector3 = ar.body.global_position - ref.global_position
		to.y = 0.0
		var look := ref.look_direction()
		look.y = 0.0
		# A positive angle about +Y is to the left.
		var left := look.normalized().signed_angle_to(to.normalized(), Vector3.UP) > 0.0
		var behind := absf(look.normalized().signed_angle_to(to.normalized(), Vector3.UP)) > deg_to_rad(120.0)
		_flag_edge.text = ("◀\nFLAG" if left else "▶\nFLAG") + ("\nBEHIND" if behind else "")
		_flag_edge.reset_size()
		_flag_edge.position = Vector2(30.0 if left else size.x - _flag_edge.size.x - 30.0, size.y * 0.45)


func _place(control: Control, at: Vector2, centred: bool) -> void:
	control.reset_size()
	var s := control.get_combined_minimum_size()
	control.position = at - (s * 0.5 if centred else Vector2.ZERO)


func _hint_text() -> String:
	var w := Controls.short(settings, &"rc_whistle")
	match m.phase:
		Match.Phase.KICK_OFF:
			if m.ai.set_piece_ready:
				return "%s   Whistle to kick off" % w
			return "Players taking their places"
		Match.Phase.SET_PIECE:
			if m.restart_needs_whistle:
				return "%s   Whistle for the restart" % w
		Match.Phase.STOPPED:
			return "Point to give the restart   ·   %s card   ·   %s dropped ball" % [
				Controls.short(settings, &"rc_yellow") + "/" + Controls.short(settings, &"rc_red"),
				Controls.short(settings, &"rc_drop")]
		Match.Phase.GOAL:
			return "Point at the centre circle to give the goal — or whistle and give a free kick"
		Match.Phase.LIVE:
			if m.half_elapsed() >= 45.0 * 60.0:
				return "Hold %s for the long whistle when time is up" % w
	return ""


func _on_decision(text: String, _good: bool) -> void:
	if text == "":
		return
	_toast_label.text = text.to_upper()
	_toast_left = 2.2


func _show_message(text: String, seconds: float) -> void:
	_message_label.text = text
	_message_left = seconds


func _on_card(player: Footballer, colour: StringName) -> void:
	var word: String = {&"yellow": "YELLOW", &"red": "RED", &"second_yellow": "SECOND YELLOW — RED"}.get(colour, "CARD")
	_notes.append("%d'  %s  %s #%d %s" % [m.match_minute(), word, player.team.short, player.number, player.player_name])
	_toast_label.text = "%s CARD — #%d %s" % [word, player.number, player.team.short] if colour != &"second_yellow" else "SECOND YELLOW — #%d %s OFF" % [player.number, player.team.short]
	_toast_left = 2.5


func _on_goal(team: Team) -> void:
	_notes.append("%d'  GOAL  %s   (%d–%d)" % [m.match_minute(), team.name, m.teams[0].goals, m.teams[1].goals])


func toggle_notebook() -> void:
	if _notebook.has_meta("open"):
		_notebook.remove_meta("open")
	else:
		_notebook.set_meta("open", true)
