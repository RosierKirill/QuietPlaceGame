class_name MobWanderState
extends State

## La créature marche jusqu'à un point tiré au hasard autour d'elle,
## puis retourne à l'inactivité.

## Rayon, en mètres, dans lequel le point de destination est tiré.
@export var wander_radius: float = 6.0
## Délai au-delà duquel on abandonne le trajet, en secondes.
@export var give_up_after: float = 6.0
## État rejoint quand une cible est repérée. Vide pour ignorer les cibles.
@export var alert_state: StringName = &""
## État rejoint une fois le point atteint.
@export var next_state: StringName = &"Idle"

@onready var _mob: Mob = get_parent().get_parent() as Mob

var _elapsed: float = 0.0


func enter() -> void:
	_elapsed = 0.0
	_mob.set_destination(_mob.random_point_around(wander_radius))


func physics_update(delta: float) -> void:
	if alert_state != &"" and _mob.acquire_target() != null:
		travel(alert_state)
		return

	_elapsed += delta
	if _mob.navigation_agent.is_navigation_finished() or _elapsed >= give_up_after:
		travel(next_state)
		return

	_mob.follow_path(delta, _mob.move_speed)
