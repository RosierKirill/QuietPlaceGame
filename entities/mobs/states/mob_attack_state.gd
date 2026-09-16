class_name MobAttackState
extends State

## La créature frappe sa cible, marque un temps de récupération,
## puis repart en poursuite.

## Chemin vers la [Hitbox] utilisée pour frapper.
@export var hitbox_path: NodePath = ^"../../Hitbox"
## Durée pendant laquelle la zone de dégâts reste ouverte, en secondes.
@export var strike_duration: float = 0.25
## Temps de récupération entre deux coups, en secondes.
@export var recovery_duration: float = 1.0
## Distance au-delà de laquelle la cible est considérée hors de portée.
@export var attack_range: float = 2.2
## État rejoint après le coup.
@export var next_state: StringName = &"Chase"

@onready var _mob: Mob = get_parent().get_parent() as Mob
@onready var _hitbox: Hitbox = get_node_or_null(hitbox_path) as Hitbox

var _elapsed: float = 0.0
var _strike_closed: bool = false


func enter() -> void:
	_elapsed = 0.0
	_strike_closed = false

	if _hitbox != null:
		_hitbox.activate()


func exit() -> void:
	if _hitbox != null:
		_hitbox.deactivate()


func physics_update(delta: float) -> void:
	_mob.stop_moving(delta)
	_elapsed += delta

	# La zone de dégâts ne reste ouverte que le temps du geste.
	if not _strike_closed and _elapsed >= strike_duration:
		_strike_closed = true
		if _hitbox != null:
			_hitbox.deactivate()

	if _elapsed >= strike_duration + recovery_duration:
		travel(next_state)
