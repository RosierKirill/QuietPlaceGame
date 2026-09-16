class_name MobChaseState
extends State

## La créature poursuit sa cible jusqu'à être à portée d'attaque,
## ou abandonne si la cible s'éloigne trop.

## Distance à laquelle l'attaque se déclenche.
@export var attack_range: float = 1.8
## État rejoint une fois à portée.
@export var attack_state: StringName = &"Attack"
## État rejoint quand la cible est perdue.
@export var lost_state: StringName = &"Idle"

@onready var _mob: Mob = get_parent().get_parent() as Mob


func physics_update(delta: float) -> void:
	if _mob.has_lost_target():
		_mob.target = null
		travel(lost_state)
		return

	if _mob.distance_to_target() <= attack_range:
		travel(attack_state)
		return

	_mob.set_destination(_mob.target.global_position)
	_mob.follow_path(delta, _mob.alert_speed)
