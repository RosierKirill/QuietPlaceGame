class_name Energy
extends Node

## Composant d'énergie (endurance).
##
## Se consomme à l'effort — le sprint pour l'instant — et se régénère
## automatiquement après un court délai sans consommation.

## Émis à chaque variation de l'énergie.
signal energy_changed(current: float, maximum: float)
## Émis quand l'énergie tombe à zéro.
signal depleted

## Énergie maximum, aussi utilisée comme valeur de départ.
@export var max_energy: float = 100.0
## Énergie régénérée par seconde.
@export var regen_per_second: float = 15.0
## Délai en secondes, sans consommation, avant que la régénération reprenne.
@export var regen_delay: float = 1.0

## Énergie courante.
var current_energy: float

## Temps écoulé depuis la dernière consommation.
var _time_since_drain: float = 0.0


func _ready() -> void:
	current_energy = max_energy
	energy_changed.emit(current_energy, max_energy)


func _process(delta: float) -> void:
	_time_since_drain += delta

	if _time_since_drain >= regen_delay and current_energy < max_energy:
		_set_energy(minf(current_energy + regen_per_second * delta, max_energy))


## Tente de consommer [param amount] d'énergie.
## Retourne false — sans rien consommer — si la réserve est insuffisante.
func try_consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current_energy < amount:
		return false

	_time_since_drain = 0.0
	_set_energy(current_energy - amount)

	if is_empty():
		depleted.emit()

	return true


## Remet l'énergie au maximum. Utilisé à la réapparition.
func restore() -> void:
	_time_since_drain = 0.0
	_set_energy(max_energy)


func is_empty() -> bool:
	return current_energy <= 0.0


func _set_energy(value: float) -> void:
	if is_equal_approx(value, current_energy):
		return

	current_energy = value
	energy_changed.emit(current_energy, max_energy)
