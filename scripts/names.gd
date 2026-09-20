class_name Names
extends RefCounted

## Fictional clubs and players. No real clubs, leagues or people (see the overview).
##
## The club names are towns that sound like somewhere, with the fictional sponsors of
## Referee For Fun among them so the two games share a world.

const CLUBS := [
	{"name": "Blueport", "short": "BLU", "shirt": Color(0.12, 0.32, 0.82), "shorts": Color(0.95, 0.95, 0.96), "keeper": Color(0.95, 0.78, 0.1), "socks": Color(0.12, 0.32, 0.82), "trim": Color(0.95, 0.95, 0.96)},
	{"name": "Halcyon", "short": "HAL", "shirt": Color(0.82, 0.12, 0.14), "shorts": Color(0.08, 0.08, 0.1), "keeper": Color(0.15, 0.75, 0.35), "socks": Color(0.82, 0.12, 0.14), "trim": Color(0.98, 0.95, 0.9)},
	{"name": "Northgate", "short": "NGT", "shirt": Color(0.95, 0.95, 0.95), "shorts": Color(0.1, 0.12, 0.3), "keeper": Color(0.9, 0.4, 0.1), "socks": Color(0.1, 0.12, 0.3), "trim": Color(0.1, 0.12, 0.3)},
	{"name": "Kestrel Town", "short": "KES", "shirt": Color(0.1, 0.55, 0.3), "shorts": Color(0.95, 0.95, 0.95), "keeper": Color(0.6, 0.2, 0.7), "socks": Color(0.1, 0.55, 0.3), "trim": Color(0.95, 0.95, 0.95)},
	{"name": "Meridian", "short": "MER", "shirt": Color(0.95, 0.72, 0.1), "shorts": Color(0.08, 0.08, 0.1), "keeper": Color(0.2, 0.5, 0.9), "socks": Color(0.08, 0.08, 0.1), "trim": Color(0.08, 0.08, 0.1)},
	{"name": "Axis Rovers", "short": "AXR", "shirt": Color(0.45, 0.15, 0.55), "shorts": Color(0.95, 0.95, 0.95), "keeper": Color(0.95, 0.85, 0.1), "socks": Color(0.45, 0.15, 0.55), "trim": Color(0.95, 0.85, 0.1)},
	{"name": "Riverside", "short": "RIV", "shirt": Color(0.45, 0.72, 0.92), "shorts": Color(0.95, 0.95, 0.96), "keeper": Color(0.9, 0.2, 0.2), "socks": Color(0.45, 0.72, 0.92), "trim": Color(0.1, 0.2, 0.4)},
	{"name": "Harbour United", "short": "HAR", "shirt": Color(0.9, 0.35, 0.08), "shorts": Color(0.1, 0.1, 0.12), "keeper": Color(0.3, 0.8, 0.4), "socks": Color(0.1, 0.1, 0.12), "trim": Color(0.95, 0.95, 0.95)},
]

const FIRST := ["Adam", "Ben", "Chris", "Danny", "Eli", "Faris", "Gabe", "Hakim", "Ivan",
	"Jamal", "Kai", "Luca", "Marco", "Nabil", "Omar", "Pablo", "Rafi", "Sam", "Tariq",
	"Umar", "Victor", "Wes", "Yusuf", "Zack", "Aiman", "Daniel", "Irfan", "Joel", "Ryan", "Theo"]
const LAST := ["Abbott", "Baker", "Carvalho", "Dawson", "Evans", "Fraser", "Grant", "Hassan",
	"Iqbal", "Jensen", "Kovac", "Lowe", "Mendes", "Nolan", "Okafor", "Park", "Quinn", "Rahman",
	"Silva", "Tan", "Usman", "Vance", "Walsh", "Yeo", "Zain", "Ismail", "Morgan", "Reid", "Hale", "Osei"]


static func club(index: int) -> Dictionary:
	return CLUBS[posmod(index, CLUBS.size())]


static func team_from(index: int) -> Team:
	var c := club(index)
	var team := Team.new()
	team.name = c.name
	team.short = c.short
	team.shirt = c.shirt
	team.shorts = c.shorts
	team.keeper_shirt = c.keeper
	team.socks = c.get("socks", c.shirt)
	team.trim = c.get("trim", Color(0.95, 0.95, 0.95))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c.name)
	team.aggression = rng.randf_range(0.3, 0.7)
	team.discipline = rng.randf_range(0.3, 0.8)
	team.honesty = rng.randf_range(0.5, 0.9)
	return team


## Eleven names for a club, the same every time for the same club.
static func squad(club_name: String, count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(club_name) * 7 + 11
	var out := []
	for i in count:
		out.append("%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]])
	return out


## Two clubs whose shirts are far enough apart to tell at a glance.
static func clash_free(home: int, away: int) -> int:
	var a: Color = club(home).shirt
	for tries in CLUBS.size():
		var b: Color = club(away + tries).shirt
		if absf(a.get_luminance() - b.get_luminance()) > 0.12 or absf(a.h - b.h) > 0.2 and absf(a.h - b.h) < 0.8:
			return posmod(away + tries, CLUBS.size())
	return away
