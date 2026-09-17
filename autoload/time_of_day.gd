extends Node

## Horloge du monde : heure, jour, et bascule jour/nuit.
##
## Autoload. Ne touche à rien d'autre : elle avance et émet des signaux. C'est
## l'éclairage, les créatures et l'interface qui s'y abonnent, ce qui permet
## d'accélérer le temps ou de le figer sans rien casser ailleurs.

## Émis à chaque changement d'heure entière.
signal hour_changed(hour: int)
## Émis au passage d'un jour au suivant.
signal day_changed(day: int)
## Émis au lever et au coucher du soleil.
signal day_night_changed(is_night: bool)

## Durée d'une journée complète, en secondes réelles.
@export var day_duration: float = 1200.0
## Heure à laquelle le soleil se lève.
@export var sunrise_hour: float = 6.0
## Heure à laquelle le soleil se couche.
@export var sunset_hour: float = 20.0
## Si faux, le temps ne s'écoule plus.
@export var running: bool = true

## Heure courante, de 0.0 à 24.0.
var time_of_day: float = 8.0
## Numéro du jour, à partir de 1.
var day: int = 1

var _last_emitted_hour: int = -1
var _was_night: bool = false


func _ready() -> void:
	_was_night = is_night()
	_last_emitted_hour = int(time_of_day)


func _process(delta: float) -> void:
	if not running or day_duration <= 0.0:
		return

	time_of_day += (delta / day_duration) * 24.0

	if time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
		day_changed.emit(day)

	_emit_hour_if_changed()
	_emit_day_night_if_changed()


## Vrai entre le coucher et le lever du soleil.
func is_night() -> bool:
	return time_of_day < sunrise_hour or time_of_day >= sunset_hour


## Progression dans la journée, de 0.0 à 1.0. Sert à piloter le soleil.
func get_day_ratio() -> float:
	return time_of_day / 24.0


## Heure au format « 14:30 ».
func get_clock_text() -> String:
	var hours := int(time_of_day)
	var minutes := int((time_of_day - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]


## Force l'heure, par exemple au chargement d'une sauvegarde.
func set_time(new_time: float, new_day: int = -1) -> void:
	time_of_day = clampf(new_time, 0.0, 24.0)
	if new_day > 0:
		day = new_day

	_emit_hour_if_changed()
	_emit_day_night_if_changed()


func _emit_hour_if_changed() -> void:
	var current_hour := int(time_of_day)
	if current_hour != _last_emitted_hour:
		_last_emitted_hour = current_hour
		hour_changed.emit(current_hour)


func _emit_day_night_if_changed() -> void:
	var night_now := is_night()
	if night_now != _was_night:
		_was_night = night_now
		day_night_changed.emit(night_now)
