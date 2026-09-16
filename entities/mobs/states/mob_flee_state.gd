class_name MobFleeState
extends State

## La créature s'éloigne de ce qui l'effraie, puis se calme une fois
## suffisamment loin.

## Distance de sécurité au-delà de laquelle la créature cesse de fuir.
@export var safe_distance: float = 14.0
## Distance parcourue à chaque nouvelle destination de fuite.
@export var flee_step: float = 6.0
## État rejoint une fois la menace distancée.
@export var calm_state: StringName = &"Idle"

@onready var _mob: Mob = get_parent().get_parent() as Mob


func enter() -> void:
	_pick_escape_destination()


func physics_update(delta: float) -> void:
	if _mob.target == null or _mob.distance_to_target() >= safe_distance:
		_mob.target = null
		travel(calm_state)
		return

	if _mob.navigation_agent.is_navigation_finished():
		_pick_escape_destination()

	_mob.follow_path(delta, _mob.alert_speed)


## Choisit un point situé à l'opposé de la menace.
func _pick_escape_destination() -> void:
	if _mob.target == null:
		return

	var away := _mob.global_position - _mob.target.global_position
	away.y = 0.0

	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD

	_mob.set_destination(_mob.global_position + away.normalized() * flee_step)
