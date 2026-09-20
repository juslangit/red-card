class_name UiTheme
extends RefCounted

## The look of the whole interface, in one place.
##
## Carried over from Referee For Fun, where Luqman asked (2026-09-08) for an interface
## noticeably larger than default and themed like a sports broadcast. Red Card keeps the
## same package — heavy condensed type, slanted plates, a gold rule — with the red of a
## card as its second colour.
##
## The point is still not decoration. An umpire has to read the score and the prompt in
## the middle of a rally, and a broadcast graphic is a design that has already been solved
## for exactly that — high contrast, heavy type, nothing thin, nothing that needs looking
## at twice.
##
## Everything lives on a Theme rather than on the individual controls. Six hundred
## lines of per-control font size overrides is how the interface got small and stayed
## small: there was no single number to change.

## The palette. Deliberately few colours — a broadcast graphic that uses six is a mess.
const INK := Color(0.055, 0.062, 0.078)
const CARD := Color(0.105, 0.118, 0.145)
const RAISED := Color(0.152, 0.170, 0.205)
const EDGE := Color(0.255, 0.285, 0.340)
const CHALK := Color(0.955, 0.960, 0.975)
const MUTED := Color(0.660, 0.700, 0.760)
const ACCENT := Color(1.000, 0.760, 0.180)
const RED := Color(0.880, 0.120, 0.140)
const YELLOW := Color(1.000, 0.840, 0.080)
const GRASS := Color(0.200, 0.470, 0.220)
const BLUE := Color(0.250, 0.520, 0.920)
const GOOD := Color(0.55, 0.85, 0.60)
const BAD := Color(0.96, 0.42, 0.36)

## The light plate a real score bug puts names on, and the pale cell a finished game sits
## in. Both are from the BWF bug, which is light rather than dark.
const PAPER := Color(0.925, 0.930, 0.940)
const PALE := Color(0.800, 0.810, 0.830)

## Every size in the interface is a multiple of these, so the whole thing grows and
## shrinks together. They were roughly two thirds of this and the interface was too
## small to read from a chair. Condensed type is narrower than the old default font at
## the same size, so the sizes went up a step when it arrived: the lines are no wider
## than they were, and taller.
const HUGE := 72
const TITLE := 50
const HEADING := 32
const BODY := 28
const SMALL := 24

## How tall a button is and how wide the wide ones are. A button you have to aim at is
## a button you will miss in the middle of a rally.
const BUTTON_HEIGHT := 68
const BUTTON_WIDTH := 460

## The typefaces. Barlow, under the SIL Open Font License (assets/fonts/OFL.txt): the
## condensed cut for anything that is a heading, a button or a number, and the semi
## condensed cut for sentences, which have to be read rather than glanced at.
const DISPLAY_FONT := "res://assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf"
const HEAVY_FONT := "res://assets/fonts/BarlowCondensed-Bold.ttf"
const STRONG_FONT := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const BODY_FONT := "res://assets/fonts/BarlowSemiCondensed-Medium.ttf"

## How far a slanted plate leans. Every broadcast package this is modelled on cuts its
## plates at an angle somewhere; a little goes a long way, and more than this starts to
## pull text off the edge of a button.
const LEAN := 0.16


static func display() -> Font:
	return load(DISPLAY_FONT)


static func heavy() -> Font:
	return load(HEAVY_FONT)


static func strong() -> Font:
	return load(STRONG_FONT)


static func body() -> Font:
	return load(BODY_FONT)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = body()
	theme.default_font_size = BODY

	_style_buttons(theme)
	_style_panels(theme)
	_style_controls(theme)
	theme.set_color("font_color", "Label", CHALK)
	theme.set_font_size("font_size", "Label", BODY)
	return theme


static func _style_buttons(theme: Theme) -> void:
	# A slanted plate with a bar of colour down the leading edge that brightens on hover.
	# It reads as a broadcast caption, and it gives the button an obvious focus state
	# without resorting to an outline, which at this size looks like a mistake.
	#
	# These four are the fallback for any button that is not made live. Every button in a
	# menu goes through `Menus.make_live()`, which replaces all four with one plate it
	# owns and tweens between dark and gold — see the long note there for why hover and
	# focus had to stop being two different looks.
	theme.set_stylebox("normal", "Button", _button_style(RAISED, ACCENT.darkened(0.45)))
	theme.set_stylebox("hover", "Button", _button_style(RAISED.lightened(0.14), ACCENT))
	theme.set_stylebox("pressed", "Button", _button_style(RAISED.darkened(0.22), ACCENT))
	theme.set_stylebox("focus", "Button", _button_style(RAISED.lightened(0.24), ACCENT))
	theme.set_stylebox("disabled", "Button", _button_style(CARD, EDGE.darkened(0.4)))

	theme.set_font("font", "Button", heavy())
	theme.set_color("font_color", "Button", CHALK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.35))
	theme.set_font_size("font_size", "Button", HEADING + 2)
	theme.set_constant("h_separation", "Button", 12)


const RESTING_EDGE := 8


## A plate a single button owns and animates for itself, rather than one of the four the
## theme hands out per state.
##
## The theme's styleboxes are shared: every Button in the game draws the same `normal` and
## the same `hover`. That is right for a stylebox nobody changes, and useless for one that
## has to be tweened, because tweening a shared box would light every button at once. A
## button that wants to animate takes a copy of the resting plate and keeps it.
##
## It starts at rest. `Menus.paint_live()` moves it from there.
static func live_button_style() -> StyleBoxFlat:
	return _button_style(RAISED, ACCENT.darkened(0.45))


static func _button_style(fill: Color, edge: Color, edge_width := RESTING_EDGE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_content_margin_all(14)
	box.content_margin_left = 30
	box.content_margin_right = 30
	box.skew = Vector2(LEAN, 0.0)
	box.border_width_left = edge_width
	box.border_color = edge
	box.anti_aliasing = true
	return box


static func _style_panels(theme: Theme) -> void:
	# A card: charcoal, square, with a thick gold rule along the top the way a broadcast
	# puts a strip of the package's colour over every full-screen graphic.
	var card := StyleBoxFlat.new()
	card.bg_color = Color(CARD.r, CARD.g, CARD.b, 0.96)
	card.set_content_margin_all(32)
	card.border_width_top = 6
	card.border_color = ACCENT
	theme.set_stylebox("panel", "PanelContainer", card)

	var plain := StyleBoxFlat.new()
	plain.bg_color = CARD
	plain.set_content_margin_all(20)
	theme.set_stylebox("panel", "Panel", plain)


## Sliders, switches and scroll bars. They were Godot's defaults — thin grey lines and a
## white knob — which is the one part of the old interface that looked unfinished rather
## than merely plain.
static func _style_controls(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	track.set_border_width_all(2)
	track.border_color = EDGE
	theme.set_stylebox("slider", "HSlider", track)

	var filled := StyleBoxFlat.new()
	filled.bg_color = ACCENT.darkened(0.15)
	filled.content_margin_top = 8
	filled.content_margin_bottom = 8
	theme.set_stylebox("grabber_area", "HSlider", filled)
	var lit := filled.duplicate()
	lit.bg_color = ACCENT
	theme.set_stylebox("grabber_area_highlight", "HSlider", lit)
	theme.set_icon("grabber", "HSlider", _knob(ACCENT, 30))
	theme.set_icon("grabber_highlight", "HSlider", _knob(Color.WHITE, 30))

	theme.set_font("font", "CheckButton", heavy())
	theme.set_font_size("font_size", "CheckButton", HEADING)
	theme.set_color("font_color", "CheckButton", CHALK)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckButton", ACCENT)
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		theme.set_stylebox(state, "CheckButton", none)
	theme.set_icon("checked", "CheckButton", _switch(true))
	theme.set_icon("unchecked", "CheckButton", _switch(false))
	theme.set_constant("h_separation", "CheckButton", 20)

	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(INK.r, INK.g, INK.b, 0.6)
	bar.content_margin_left = 6
	bar.content_margin_right = 6
	theme.set_stylebox("scroll", "VScrollBar", bar)
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = EDGE
	thumb.content_margin_left = 6
	thumb.content_margin_right = 6
	theme.set_stylebox("grabber", "VScrollBar", thumb)
	var thumb_lit := thumb.duplicate()
	thumb_lit.bg_color = ACCENT
	theme.set_stylebox("grabber_hover", "VScrollBar", thumb_lit)
	theme.set_stylebox("grabber_pressed", "VScrollBar", thumb_lit)


## A switch drawn in code: a gold track with the knob to the right when it is on, a dark
## one with the knob to the left when it is off. Godot's own is a small grey pill that
## was all but invisible against the card.
static func _switch(on: bool) -> ImageTexture:
	var w := 76
	var h := 38
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(0, 0, w, h), EDGE)
	image.fill_rect(Rect2i(3, 3, w - 6, h - 6), ACCENT if on else INK)
	var knob := h - 12
	var x := w - knob - 6 if on else 6
	image.fill_rect(Rect2i(x, 6, knob, knob), INK if on else MUTED)
	return ImageTexture.create_from_image(image)


## A square knob drawn in code, so the slider needs no image file.
static func _knob(colour: Color, size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var inset := 3
	image.fill_rect(Rect2i(inset, inset, size - inset * 2, size - inset * 2), INK)
	image.fill_rect(Rect2i(inset + 3, inset + 3, size - inset * 2 - 6, size - inset * 2 - 6), colour)
	return ImageTexture.create_from_image(image)


## A plate for a line of HUD text: dark, slightly transparent, with a coloured edge.
## Used for anything that has to stay readable over a lit green court, which is
## everything — white text on that background is legible about half the time.
static func plate(edge := ACCENT, alpha := 0.80) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(INK.r, INK.g, INK.b, alpha)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.border_width_left = 6
	box.border_color = edge
	return box


## A solid block of a colour, for a score bug cell or a tag.
static func block(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## A slanted block: a tag, a header strip, the edge of a lower third.
static func slant(colour: Color, lean := LEAN) -> StyleBoxFlat:
	var box := block(colour)
	box.skew = Vector2(lean, 0.0)
	box.anti_aliasing = true
	return box


## A label in one of the heavy faces. `font` is one of the functions above.
static func label(text: String, size: int, colour: Color, font: Font = null) -> Label:
	var made := Label.new()
	made.text = text
	made.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	made.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	made.add_theme_font_size_override("font_size", size)
	made.add_theme_color_override("font_color", colour)
	if font != null:
		made.add_theme_font_override("font", font)
	return made
