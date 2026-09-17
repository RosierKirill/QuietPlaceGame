class_name NeedEffects
extends Node

## Traduit l'état des besoins en conséquences sur la santé.
##
## Séparé de [Need], qui ne doit rien savoir de la santé, et de [Health], qui
## ne doit rien savoir de la faim. Ce nœud est le seul endroit où les deux se
## rencontrent, ce qui permet de changer les règles de survie sans toucher aux
## composants eux-mêmes.

## Dégâts par seconde, pour chaque besoin tombé à zéro. Deux besoins vides
## font donc deux fois plus mal.
@export var damage_per_second: float = 2.0

@onready var _health: Health = _find_health()

var _needs: Array[Need] = []


func _ready() -> void:
	_needs = _find_needs()

	if _health == null:
		push_warning("NeedEffects : aucun Health trouvé sur '%s'." % get_parent())


func _physics_process(delta: float) -> void:
	if _health == null or _health.is_dead():
		return

	var empty_count := 0
	for need in _needs:
		if need.is_depleted():
			empty_count += 1

	if empty_count > 0:
		_health.take_damage(damage_per_second * empty_count * delta, self)


## Vrai si au moins un besoin est au niveau critique. Sert à brider l'effort.
func has_critical_need() -> bool:
	for need in _needs:
		if need.is_critical():
			return true
	return false


func _find_health() -> Health:
	for child in get_parent().get_children():
		if child is Health:
			return child as Health
	return null


func _find_needs() -> Array[Need]:
	var found: Array[Need] = []
	for child in get_parent().get_children():
		if child is Need:
			found.append(child as Need)
	return found
