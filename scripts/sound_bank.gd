class_name SoundBank
extends Node3D

## Every sound in a match: the whistle, boots on the ball, the crowd.
##
## The whistle and the referee's own footsteps are not positioned — they are the player's
## own, and come from inside their head. The ball is heard where it is. The crowd is a
## bed that swells when something happens.

const WHISTLE_SHORT := "res://assets/audio/whistle_short.wav"
const WHISTLE_FIRM := "res://assets/audio/whistle_firm.wav"
const WHISTLE_LONG := "res://assets/audio/whistle_long.wav"
const KICKS := ["res://assets/audio/kick_1.wav", "res://assets/audio/kick_2.wav", "res://assets/audio/kick_3.wav"]
const STEPS := ["res://assets/audio/steps/grass_1.wav", "res://assets/audio/steps/grass_2.wav",
	"res://assets/audio/steps/grass_3.wav", "res://assets/audio/steps/grass_4.wav"]

var _bed: AudioStreamPlayer
var _swell: AudioStreamPlayer
var _whistle: AudioStreamPlayer
var _flat: AudioStreamPlayer
var _kicks: Array[AudioStreamPlayer3D] = []
var _next_kick := 0
var _crowd_size := 0.5


func _ready() -> void:
	Settings.ensure_buses()
	_bed = _player("Crowd")
	_swell = _player("Crowd")
	_whistle = _player("Effects")
	_flat = _player("Effects")
	for i in 4:
		var k := AudioStreamPlayer3D.new()
		k.bus = "Effects"
		k.unit_size = 12.0
		k.max_db = 3.0
		add_child(k)
		_kicks.append(k)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _load(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


func start_bed(level: Dictionary) -> void:
	var path := "res://assets/audio/crowd/small_walla.mp3"
	_crowd_size = 0.3
	if level.crowd >= 4000:
		path = "res://assets/audio/crowd/stadium_bed.ogg"
		_crowd_size = 1.0
	elif level.crowd >= 500:
		path = "res://assets/audio/crowd/football_ambience.mp3"
		_crowd_size = 0.6
	var stream := _load(path)
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_bed.stream = stream
	_bed.volume_db = linear_to_db(0.35 + _crowd_size * 0.4)
	_bed.play()


func whistle(long := false, firm := false) -> void:
	_whistle.stream = _load(WHISTLE_LONG if long else (WHISTLE_FIRM if firm else WHISTLE_SHORT))
	_whistle.play()


func kick(where: Vector3, speed: float) -> void:
	var k := _kicks[_next_kick]
	_next_kick = (_next_kick + 1) % _kicks.size()
	k.stream = _load(KICKS[randi() % KICKS.size()])
	k.global_position = where
	k.volume_db = linear_to_db(clampf(speed / 25.0, 0.25, 1.0))
	k.pitch_scale = randf_range(0.92, 1.08)
	k.play()


func thud(where: Vector3) -> void:
	kick(where, 8.0)


func step() -> void:
	_flat.stream = _load(STEPS[randi() % STEPS.size()])
	_flat.volume_db = -8.0
	_flat.pitch_scale = randf_range(0.9, 1.1)
	_flat.play()


func flag_beep() -> void:
	# The electronic beep flag a professional assistant uses buzzes on the referee's arm.
	_flat.stream = _load("res://assets/audio/ui/review_open.ogg")
	_flat.volume_db = -4.0
	_flat.pitch_scale = 1.6
	_flat.play()


func roar(home: bool) -> void:
	_swell_with("res://assets/audio/crowd/goal_chant.ogg" if _crowd_size > 0.8 else "res://assets/audio/crowd/goal_roar.mp3", 1.0)


func groan() -> void:
	_swell_with("res://assets/audio/crowd/groan.wav", 0.8)


func boo(_home_side: bool) -> void:
	_swell_with("res://assets/audio/crowd/boo.mp3", 0.5 + _crowd_size * 0.5)


func crowd_reacts(amount: float) -> void:
	_swell_with("res://assets/audio/crowd/oooh.mp3", amount * _crowd_size)


func cheer() -> void:
	_swell_with("res://assets/audio/crowd/cheer.wav", 0.7)


func _swell_with(path: String, loudness: float) -> void:
	_swell.stream = _load(path)
	_swell.volume_db = linear_to_db(clampf(loudness * (0.4 + _crowd_size * 0.6), 0.05, 1.0))
	_swell.play()
