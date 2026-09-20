extends Node

## Just enough of the Play scene for the report screen to open against, so the report can
## be looked at without playing a match to the end by hand. See dev/looks/_report.gd.

var m: Match
var replay: ReplayViewer
var config := {"mode": "quick"}


func leave() -> void:
	get_tree().quit()


func retry() -> void:
	get_tree().quit()
