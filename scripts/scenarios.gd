class_name Scenarios
extends RefCounted

## Training drills and scenario challenges: one incident each, set up by hand.
##
## A drill teaches one verb and says what to do; a challenge sets up a real refereeing
## problem — the last man, the dive, the handball on the line — and says nothing about the
## answer. Both are the ordinary match with a script on top: players placed, the ball
## given to somebody, and the incident made to happen at a set moment. The Laws record it
## exactly as they would in a match, and the Assessor judges the player's response the
## same way too, so what is learned here is what is marked in the career.
##
## Coordinates are for the town ground (102 x 68), with the home side (0) attacking +X:
## its penalty area starts at x = 34.5 and the penalty spot is at x = 40.

const LIST := [
	# --- training -------------------------------------------------------------------------
	{"id": "t_move", "mode": "training", "title": "Find your legs",
		"brief": "WASD to move · SHIFT to sprint · MOUSE to look.\nLook down — that is you. Jog to each of the three glowing markers. Sprinting drains stamina (bottom left); jogging gets it back.",
		"ref_at": Vector3(-20, 0, 0), "markers": [Vector3(-5, 0, 12), Vector3(12, 0, -14), Vector3(28, 0, 6)],
		"next": "t_foul"},
	{"id": "t_foul", "mode": "training", "title": "Blow for a foul",
		"brief": "Watch the Blueport striker, number 9.\nIf he is fouled: WHISTLE (left click), then POINT (right click) the way Blueport are attacking. The line under the crosshair says what your point would give. Whistle again to restart.",
		"ref_at": Vector3(-6, 0, -9), "ref_look": Vector3(10, 0, 3),
		"place": [[0, 9, Vector3(0, 0, 4)], [1, 5, Vector3(-2.5, 0, 5)]],
		"give": [0, 9], "run": [[0, 9, Vector3(30, 0, 3)], [1, 5, Vector3(30, 0, 3)]],
		"script": [{"t": 2.4, "do": "foul", "by": [1, 5], "on": [0, 9], "severity": "careless", "behind": true}],
		"judge": "foul", "law": "Law 12: a careless trip is a direct free kick to the other side, where it happened.",
		"next": "t_penalty"},
	{"id": "t_penalty", "mode": "training", "title": "Inside the box",
		"brief": "A foul by a defender inside his own penalty area is a penalty.\nIf you see one: WHISTLE, then POINT at the penalty spot (look down at it — the prompt will say PENALTY).",
		"ref_at": Vector3(24, 0, -11), "ref_look": Vector3(40, 0, 0),
		"place": [[0, 9, Vector3(29, 0, 4)], [1, 6, Vector3(31, 0, 7)]],
		"give": [0, 9], "run": [[0, 9, Vector3(46, 0, 1)], [1, 6, Vector3(44, 0, 2)]],
		"script": [{"t": 1.7, "do": "foul", "by": [1, 6], "on": [0, 9], "severity": "careless", "behind": false}],
		"judge": "foul", "law": "Law 14: a direct free kick offence by a defender in his own penalty area is a penalty kick.",
		"next": "t_advantage"},
	{"id": "t_advantage", "mode": "training", "title": "Play on",
		"brief": "Not every foul needs the whistle. If the team that was fouled keeps the ball and a good attack, stopping play punishes them.\nWhen Blueport's number 10 is fouled and keeps going: press SPACE — advantage — and let it run.",
		"ref_at": Vector3(-14, 0, -10), "ref_look": Vector3(5, 0, 0),
		"place": [[0, 10, Vector3(-6, 0, -3)], [1, 4, Vector3(-7.5, 0, -1.5)], [0, 9, Vector3(10, 0, 4)], [0, 11, Vector3(8, 0, -16)]],
		"give": [0, 10], "run": [[0, 10, Vector3(25, 0, -2)], [1, 4, Vector3(25, 0, -2)]],
		"script": [{"t": 1.8, "do": "foul", "by": [1, 4], "on": [0, 10], "severity": "careless", "behind": true, "stays_up": true},
			{"t": 3.6, "do": "release"}],
		"end_after": 7.0,
		"judge": "foul", "law": "Law 5: the referee allows play to continue when the team against which an offence has been committed will benefit.",
		"next": "t_card"},
	{"id": "t_card", "mode": "training", "title": "Show a card",
		"brief": "A reckless challenge is a caution.\nWHISTLE, POINT for the free kick, then LOOK AT the player who made the tackle and press Y. Whistle again to restart.",
		"ref_at": Vector3(-10, 0, -8), "ref_look": Vector3(4, 0, 2),
		"place": [[0, 8, Vector3(-2, 0, 2)], [1, 7, Vector3(-5, 0, 4)]],
		"give": [0, 8], "run": [[0, 8, Vector3(20, 0, 2)], [1, 7, Vector3(20, 0, 2)]],
		"script": [{"t": 2.0, "do": "foul", "by": [1, 7], "on": [0, 8], "severity": "reckless", "behind": true, "sliding": true}],
		"judge": "foul", "law": "Law 12: reckless — acting with disregard to the danger to, or consequences for, an opponent — must be cautioned.",
		"next": "t_out"},
	{"id": "t_out", "mode": "training", "title": "Over the line",
		"brief": "When the ball crosses the goal line, what matters is who touched it last.\nOff a defender: POINT at the corner flag — a corner. Off an attacker: POINT at the goal area — a goal kick.",
		"ref_at": Vector3(32, 0, -12), "ref_look": Vector3(50, 0, -4),
		"place": [[1, 2, Vector3(44, 0, -9)], [0, 11, Vector3(40, 0, -12)]],
		"script": [{"t": 1.2, "do": "kick", "by": [1, 2], "from": Vector3(44.5, 0, -9), "velocity": Vector3(9, 0.5, 1)}],
		"judge": "out", "law": "Law 17: when the whole of the ball passes over the goal line, having last touched a defender, it is a corner kick.",
		"next": "t_throw"},
	{"id": "t_throw", "mode": "training", "title": "Throw-in",
		"brief": "Over the touchline: a throw-in to the other team from the one that touched it last.\nPOINT along the line the way the team taking it is attacking.",
		"ref_at": Vector3(-4, 0, -14), "ref_look": Vector3(5, 0, -30),
		"place": [[0, 7, Vector3(4, 0, -26)], [1, 3, Vector3(6, 0, -24)]],
		"script": [{"t": 1.0, "do": "kick", "by": [0, 7], "from": Vector3(4.5, 0, -27), "velocity": Vector3(2, 0.3, -8)}],
		"judge": "out", "law": "Law 15: a throw-in is awarded to the opponents of the player who last touched the ball.",
		"next": "t_offside"},
	{"id": "t_offside", "mode": "training", "title": "Your assistant's flag",
		"brief": "Your assistant referees watch for offside from the touchline. When a flag goes up, the call is still yours.\nA flag with the play offside: WHISTLE to accept it. If you are sure it is wrong: press X to wave it down.",
		"ref_at": Vector3(18, 0, -6), "ref_look": Vector3(34, 0, 4),
		"place": [[0, 8, Vector3(16, 0, 2)], [0, 9, Vector3(40, 0, 9)], [1, 5, Vector3(36, 0, -2)], [1, 6, Vector3(36.2, 0, -10)], [0, 10, Vector3(22, 0, -14)]],
		"clear_ahead": true,
		"give": [0, 8],
		"run": [[0, 9, Vector3(44, 0, 9)]],
		"hold": [[1, 5], [1, 6], [0, 10]],
		"script": [{"t": 1.2, "do": "pass", "by": [0, 8], "to": [0, 9]}],
		"level": "town", "judge": "offside", "law": "Law 11: a player in an offside position when the ball is played by a teammate commits an offence by becoming involved in play.",
		"next": "t_foul_flag"},
	{"id": "t_foul_flag", "mode": "training", "title": "Behind your back",
		"brief": "Your assistants also flag fouls near them that you cannot see. A foul flag is WAGGLED; an offside flag is held still.\nA big arrow at the edge of the screen shows which way to turn, and a yellow flag marks the assistant. WHISTLE to accept, then POINT the free kick the way the assistant's flag points.",
		"ref_at": Vector3(2, 0, -6), "ref_look": Vector3(-20, 0, -6),
		"place": [[0, 7, Vector3(12, 0, 26)], [1, 3, Vector3(9.5, 0, 27)]],
		"give": [0, 7], "run": [[0, 7, Vector3(34, 0, 28)], [1, 3, Vector3(34, 0, 28)]],
		"script": [{"t": 1.8, "do": "foul", "by": [1, 3], "on": [0, 7], "severity": "careless", "behind": true, "flagged": true}],
		"end_after": 9.0,
		"judge": "foul", "law": "Law 6: assistant referees indicate when an offence has been committed out of the referee's view, or when they are better placed to see it.",
		"next": "t_time"},
	{"id": "t_time", "mode": "training", "title": "Keep the time",
		"brief": "You are the timekeeper. Hold TAB to raise your watch.\nTwo minutes have been lost this half. When your watch passes 92:00, HOLD the whistle for the long blast to end the match.",
		"ref_at": Vector3(0, 0, -8), "clock": {"half": 2, "minute": 44.0, "lost": 100.0},
		"judge": "time", "law": "Law 7: the referee allows for all time lost in each half and ends it when that time is up."},

	# --- challenges -----------------------------------------------------------------------
	{"id": "s_last_man", "mode": "scenario", "title": "The last man",
		"brief": "Blueport's number 9 is through on goal. Referee it.",
		"ref_at": Vector3(8, 0, -12), "ref_look": Vector3(24, 0, 0),
		"place": [[0, 9, Vector3(16, 0, 0)], [1, 5, Vector3(14, 0, -2)], [1, 6, Vector3(4, 0, 6)], [1, 2, Vector3(2, 0, -14)], [1, 3, Vector3(3, 0, 16)]],
		"clear_ahead": true,
		"give": [0, 9], "run": [[0, 9, Vector3(44, 0, 0)], [1, 5, Vector3(44, 0, 0)]],
		"script": [{"t": 1.9, "do": "foul", "by": [1, 5], "on": [0, 9], "severity": "careless", "behind": true}],
		"judge": "foul", "law": "Law 12: denying an obvious goal-scoring opportunity outside the penalty area is a sending-off."},
	{"id": "s_dive", "mode": "scenario", "title": "In the box",
		"brief": "Blueport's number 10 takes it into the area. Referee it.",
		"ref_at": Vector3(26, 0, -11), "ref_look": Vector3(40, 0, 2),
		"place": [[0, 10, Vector3(31, 0, 3)], [1, 4, Vector3(33, 0, 5)]],
		"give": [0, 10], "run": [[0, 10, Vector3(46, 0, 0)], [1, 4, Vector3(45, 0, 3)]],
		"script": [{"t": 1.4, "do": "dive", "by": [0, 10]}],
		"end_after": 7.0,
		"judge": "simulation", "law": "Law 12: attempting to deceive the referee by pretending to have been fouled is a caution for unsporting behaviour."},
	{"id": "s_handball", "mode": "scenario", "title": "On the line",
		"brief": "The keeper has come out and been beaten. A shot from the edge of the area. Referee it.",
		"ref_at": Vector3(28, 0, -12), "ref_look": Vector3(46, 0, 0),
		"place": [[0, 9, Vector3(36, 0, 2)], [1, 3, Vector3(49.5, 0, 1.2)], [1, 1, Vector3(44, 0, -7)]],
		"hold": [[1, 3], [1, 1]],
		"brief_note": "The keeper has come out and been beaten.",
		"give": [0, 9],
		"script": [{"t": 0.8, "do": "shoot", "by": [0, 9], "at": Vector3(51, 1.25, 1.2)}, {"t": 0.9, "do": "arms", "by": [1, 3]}],
		"judge": "handball", "law": "Law 12: denying a goal by deliberately handling the ball is a sending-off, and the restart is a penalty."},
	{"id": "s_holding", "mode": "scenario", "title": "The pull",
		"brief": "Blueport's number 6 makes a run into the area. Referee it.",
		"ref_at": Vector3(28, 0, -14), "ref_look": Vector3(42, 0, 0),
		"place": [[0, 6, Vector3(34, 0, 8)], [1, 5, Vector3(33, 0, 9)], [0, 8, Vector3(24, 0, -16)]],
		"give": [0, 8], "run": [[0, 6, Vector3(44, 0, 2)], [1, 5, Vector3(44, 0, 3)]],
		"script": [{"t": 1.3, "do": "hold", "by": [1, 5], "on": [0, 6]}],
		"judge": "holding", "law": "Law 12: holding an opponent is a direct free kick — inside the defender's own area, a penalty."},
	{"id": "s_hit", "mode": "scenario", "title": "In the way",
		"brief": "Stand still where you are. Referee what happens.",
		"ref_at": Vector3(4, 0, 0.3), "ref_look": Vector3(-6, 0, 0), "ref_still": true,
		"place": [[0, 8, Vector3(-6, 0, 0)], [0, 10, Vector3(16, 0, 0)], [1, 4, Vector3(0, 0, 4)]],
		"run_after": [[0, 8, Vector3(-16, 0, 12)]],
		"give": [0, 8],
		"script": [{"t": 0.8, "do": "kick", "by": [0, 8], "from": Vector3(-5.4, 0, 0), "velocity": Vector3(14, 0, 0)}],
		"judge": "hit_referee", "law": "Law 9: if the ball touches the referee and possession changes, it is a dropped ball to the team that last had it."},
	{"id": "s_advantage_card", "mode": "scenario", "title": "Advantage, then the card",
		"brief": "Blueport are breaking. Referee it — all of it.",
		"ref_at": Vector3(-12, 0, -10), "ref_look": Vector3(6, 0, 0),
		"place": [[0, 10, Vector3(-4, 0, -2)], [1, 8, Vector3(-6, 0, -0.5)], [0, 9, Vector3(14, 0, 5)]],
		"give": [0, 10], "run": [[0, 10, Vector3(30, 0, -4)], [1, 8, Vector3(28, 0, -3)]],
		"script": [{"t": 1.7, "do": "foul", "by": [1, 8], "on": [0, 10], "severity": "reckless", "behind": true, "stays_up": true},
			{"t": 5.5, "do": "shoot", "by": [0, 10], "at": Vector3(51, 0.6, 9.5)}],
		"end_on_restart": true,
		"judge": "foul", "law": "Law 12: when advantage is played for an offence that deserves a caution, the caution is given when the ball is next out of play."},
	{"id": "s_flag", "mode": "scenario", "title": "The flag",
		"brief": "A ball over the top for Blueport's number 9. Your assistant has a view. So do you.",
		"ref_at": Vector3(30, 0, -3), "ref_look": Vector3(36, 0, 8),
		"place": [[0, 8, Vector3(14, 0, 4)], [0, 9, Vector3(35.9, 0, 11)], [1, 5, Vector3(36, 0, 1)], [1, 6, Vector3(36.2, 0, -7)]],
		"clear_ahead": true,
		"give": [0, 8],
		"run": [[0, 9, Vector3(40, 0, 11)]],
		"script": [{"t": 1.0, "do": "pass", "by": [0, 8], "to": [0, 9]}, {"t": 2.2, "do": "false_flag", "on": [0, 9]}],
		"level": "town", "judge": "flag", "law": "Law 11: a player level with the second-last opponent is not in an offside position. The assistant advises; the referee decides."},
	{"id": "s_backpass", "mode": "scenario", "title": "Back to the keeper",
		"brief": "Halcyon play it back to their goalkeeper. Referee it.",
		"ref_at": Vector3(30, 0, -12), "ref_look": Vector3(44, 0, 0),
		"place": [[1, 5, Vector3(36, 0, 4)], [0, 9, Vector3(30, 0, 6)]],
		"script": [{"t": 0.8, "do": "kick", "by": [1, 5], "from": Vector3(36.5, 0, 4), "velocity": Vector3(9, 0, -1.6), "kind": "pass"},
			{"t": 2.4, "do": "keeper_picks_up", "team": 1}],
		"judge": "back_pass", "law": "Law 12: an indirect free kick is awarded if a goalkeeper handles the ball after it has been deliberately kicked to him by a teammate."},
]


static func find(id: String) -> Dictionary:
	for s in LIST:
		if s.id == id:
			return s
	return {}


static func of_mode(mode: String) -> Array:
	return LIST.filter(func(s): return s.mode == mode)


static func start(id: String, m: Match, ref: Referee, hud: Hud) -> ScenarioRun:
	var run := ScenarioRun.new()
	run.def = find(id)
	run.m = m
	run.ref = ref
	run.hud = hud
	return run
