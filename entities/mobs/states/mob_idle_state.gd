class_name MobIdleState
extends State

## La créature s'arrête un moment, puis repart en errance.
## Si elle repère une cible, elle bascule vers l'état d'alerte configuré.

## Durée minimale de la pause, en secondes.
@export var minimum_duration: float = 1.0
## Durée maximale de la pause, en secondes.
@export var maximum_duration: float = 3.0
## État rejoint quand une cible est repérée. Vide pour ignorer les cibles.
@export var alert_state: StringName = &""
## État rejoint à la fin de la pause.
@export var next_state: StringName = &"Wander"

@onready var _mob: Mob = get_parent().get_parent() as Mob

var _remaining: float = 0.0


func enter() -> void:
	_remaining = randf_range(minimum_duration, maximum_duration)


func physics_update(delta: float) -> void:
	_mob.stop_moving(delta)

	if alert_state != &"" and _mob.acquire_target() != null:
		travel(alert_state)
		return

	_remaining -= delta
	if _remaining <= 0.0:
		travel(next_state)
