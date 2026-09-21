class_name Cutscenes
extends RefCounted

## The four scenes, written as shots over the real pitch. See `Cutscene` for how a shot is
## described; everything here is only geometry — where to put the camera, what to look at,
## and for how long.
##
## They are all short on purpose. A referee's game is the ninety minutes; these are the
## moments either side of it, and none of them is worth more than about eight seconds.

## Before kick-off: out of the tunnel, down the line, and into the middle.
##
## The players are put on the touchline and walk to their kick-off positions while the
## camera films them, so what you are watching is the real twenty-two finding their shape
## rather than a clip of somebody else's.
static func walkout(m, ref) -> Array:
	var spec: PitchSpec = m.spec
	var side: float = spec.half_width() + 3.0
	var middle := Vector3.ZERO
	return [
		# The ground, empty, from behind the near goal.
		{"from": Vector3(-spec.length * 0.5 - 16.0, 9.0, 6.0),
		 "to": Vector3(-spec.length * 0.5 - 9.0, 6.0, 2.0),
		 "look": Vector3(0, 1.5, 0), "seconds": 3.2, "fov": 52.0,
		 "caption": m.level.name.to_upper()},
		# Down the touchline as they come out.
		{"from": Vector3(-26.0, 3.2, side + 5.0), "to": Vector3(-4.0, 2.6, side + 3.0),
		 "look": Vector3(-14.0, 1.2, side - 2.0), "look_to": Vector3(6.0, 1.2, side - 2.0),
		 "seconds": 3.6, "fov": 44.0,
		 "caption": "%s v %s" % [m.teams[0].name.to_upper(), m.teams[1].name.to_upper()]},
		# And you, walking out last, as a referee does. The camera stands on the pitch
		# side of him: put it on the other side and it films from inside the stand.
		{"from": ref.global_position + Vector3(2.6, 1.9, 0.0) + _inward(ref) * 4.5,
		 "to": ref.global_position + Vector3(1.4, 1.7, 0.0) + _inward(ref) * 2.6,
		 "follow": ref, "seconds": 2.8, "fov": 40.0,
		 "caption": "YOU ARE THE REFEREE"},
		{"from": Vector3(0, 12.0, 26.0), "to": Vector3(0, 7.0, 18.0),
		 "look": middle, "seconds": 2.6, "fov": 50.0},
	]


## Away from whichever touchline somebody is standing on, towards the middle of the pitch.
static func _inward(node) -> Vector3:
	var z: float = (node as Node3D).global_position.z
	return Vector3(0, 0, -signf(z) if absf(z) > 0.1 else -1.0)


## A goal: the man who scored, then the noise.
static func goal(m, scorer) -> Array:
	var where: Vector3 = scorer.global_position if scorer != null else Vector3.ZERO
	# In front of him, not behind: a man celebrating is worth filming from the front, and
	# his heading is where he is facing.
	var face: Vector3 = scorer.heading if scorer != null else Vector3.FORWARD
	return [
		{"from": where + face * 3.2 + Vector3(0, 1.8, 0),
		 "to": where + face * 5.0 + Vector3(0, 2.6, 0),
		 "follow": scorer, "seconds": 2.8, "fov": 34.0, "fov_to": 44.0,
		 "caption": "GOAL"},
	]


## A sending-off: the player, the long walk, and nothing said.
static func red_card(m, player) -> Array:
	if player == null:
		return []
	var face: Vector3 = player.global_position + player.heading * 3.4 + Vector3(0, 1.7, 0)
	return [
		{"from": face, "to": face + player.heading * -0.8 + Vector3(0, 0.1, 0),
		 "follow": player, "seconds": 2.4, "fov": 34.0, "caption": "OFF"},
	]


## The end of a career: the last whistle at the cup final, and the walk off.
static func ceremony(m, ref) -> Array:
	return [
		{"from": ref.global_position + Vector3(3.0, 2.0, 5.0),
		 "to": ref.global_position + Vector3(1.5, 1.8, 3.0),
		 "follow": ref, "seconds": 3.0, "fov": 40.0, "caption": "FULL TIME"},
		{"from": Vector3(0, 6.0, 20.0), "to": Vector3(0, 22.0, 46.0),
		 "look": Vector3(0, 1.0, 0), "seconds": 4.2, "fov": 46.0, "fov_to": 54.0,
		 "caption": "THE CUP FINAL, REFEREED"},
	]


## The title: the empty ground the menu is already standing in, and the name. Three shots,
## ten seconds, skippable on any key — which matters most here, because this is the one a
## player sees every time they launch the game.
static func title(_spec = null) -> Array:
	return [
		# Low along the halfway line, drifting towards the middle.
		{"from": Vector3(-44.0, 1.6, 26.0), "to": Vector3(-22.0, 2.4, 18.0),
		 "look": Vector3(0, 1.0, -4.0), "look_to": Vector3(4.0, 1.0, 0.0),
		 "seconds": 3.6, "fov": 44.0},
		# Up and over the centre circle.
		{"from": Vector3(6.0, 3.0, 14.0), "to": Vector3(2.0, 9.0, 22.0),
		 "look": Vector3(0, 0.2, 0), "seconds": 3.2, "fov": 40.0, "fov_to": 50.0},
		# And the name, from the far corner with the stand behind it.
		{"from": Vector3(28.0, 2.0, 22.0), "to": Vector3(20.0, 1.6, 16.0),
		 "look": Vector3(0, 0.6, 0), "seconds": 3.2, "fov": 36.0,
		 "caption": "RED CARD", "size": UiTheme.HUGE},
	]
