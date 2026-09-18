class_name Incident
extends RefCounted

## One thing that happened which the Laws of the Game have an answer for.
##
## Written the moment it happens, by `Laws`, from what really took place. It holds the
## truth and the right answer; the referee's reaction is attached to it afterwards and
## the two are compared by the `Assessor`. Nothing the player can see during the match
## ever reads the truth half of this object.

var kind: StringName          # foul, holding, handball, simulation, offside, out, goal,
                              # back_pass, hit_referee, dissent, serious_injury
var time := 0.0               # match clock, seconds
var minute := 0               # match minute, for the report
var position := Vector3.ZERO
var offender: Footballer = null
var victim: Footballer = null
var severity := Laws.Severity.NONE
var details := {}

## The right answer.
var expected_restart := &""     # free_kick, indirect_free_kick, penalty, throw_in, corner,
                                # goal_kick, kick_off, dropped_ball, play_on
var expected_team: Team = null  # who takes the restart
var expected_card := &""        # "", yellow, red
var card_reason := ""           # for the report: "stopping a promising attack", ...
var dogso := false
var spa := false
## Whether the referee should have stopped play for this (a foul with advantage on is
## still a foul, but stopping play is not then required).
var must_stop := true
## How long after it the whistle still counts as a response to it.
var window := 3.5
## Key match incident: a goal, a penalty, a red card, or anything that decides one.
var key := false

## What the referee did about it, filled in as it happens.
var whistled := false
var whistle_time := -1.0
var advantage := false
var advantage_time := -1.0
var restart_given := &""
var restart_team: Team = null
var cards_given: Array = []     # [{player, colour}]
var resolved := false
var verdict := ""               # the assessor's line about it
var points := 0.0
## Where the referee was, and how well placed, at the moment it happened.
var ref_distance := 0.0
var ref_view := 1.0
## Whether VAR has looked at it.
var reviewed := false
var overturned := false


func label() -> String:
	match kind:
		&"foul":
			var how := "Foul"
			if severity == Laws.Severity.EXCESSIVE:
				how = "Serious foul play"
			elif severity == Laws.Severity.RECKLESS:
				how = "Reckless challenge"
			return "%s by %s on %s" % [how, who(offender), who(victim)]
		&"holding":
			return "%s holds %s" % [who(offender), who(victim)]
		&"handball":
			return "Handball by %s" % who(offender)
		&"simulation":
			return "Dive by %s" % who(offender)
		&"offside":
			return "Offside, %s" % who(offender)
		&"out":
			return "Ball out of play"
		&"goal":
			return "Goal by %s" % who(offender)
		&"back_pass":
			return "Keeper handles a back-pass"
		&"hit_referee":
			return "Ball hits the referee"
		&"dissent":
			return "Dissent by %s" % who(offender)
		&"serious_injury":
			return "%s injured" % who(victim)
	return String(kind)


static func who(p: Footballer) -> String:
	if p == null:
		return "?"
	return "%s #%d" % [p.team.short, p.number]
