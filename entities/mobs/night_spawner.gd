class_name NightSpawner
extends Node3D

## Fait apparaître des créatures à la tombée de la nuit, hors du champ de vision.
##
## Plafonne leur nombre et les retire au lever du jour, pour que la nuit soit
## une pression temporaire et non une accumulation.

## Scène de la créature à faire apparaître.
@export var mob_scene: PackedScene
## Nombre maximum de créatures vivantes issues de ce générateur.
@export var maximum_alive: int = 6
## Intervalle entre deux apparitions, en secondes.
@export var spawn_interval: float = 12.0
## Distance minimale au joueur, pour ne pas apparaître sous son nez.
@export var minimum_distance: float = 18.0
## Distance maximale au joueur.
@export var maximum_distance: float = 30.0
## Si vrai, les créatures issues de ce générateur disparaissent au matin.
@export var despawn_at_dawn: bool = true
## Groupe du joueur, autour duquel on calcule les distances.
@export var player_group: StringName = &"player"

## Créatures encore vivantes issues de ce générateur.
var _spawned: Array[Node3D] = []
var _timer: float = 0.0


func _ready() -> void:
	TimeOfDay.day_night_changed.connect(_on_day_night_changed)


func _process(delta: float) -> void:
	_forget_dead()

	if not TimeOfDay.is_night() or mob_scene == null:
		return
	if _spawned.size() >= maximum_alive:
		return

	_timer += delta
	if _timer < spawn_interval:
		return

	_timer = 0.0
	_spawn_one()


func _spawn_one() -> void:
	var player := _find_player()
	if player == null:
		return

	var mob := mob_scene.instantiate() as Node3D
	get_parent().add_child(mob)
	mob.global_position = _pick_position_around(player.global_position)
	_spawned.append(mob)


## Tire un point à distance du joueur, dans une direction quelconque.
func _pick_position_around(center: Vector3) -> Vector3:
	var angle := randf() * TAU
	var distance := randf_range(minimum_distance, maximum_distance)
	return center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


## Retire les créatures de la nuit écoulée.
func _on_day_night_changed(is_night: bool) -> void:
	_timer = 0.0

	if is_night or not despawn_at_dawn:
		return

	for mob in _spawned:
		if is_instance_valid(mob):
			mob.queue_free()

	_spawned.clear()


## Oublie celles qui sont mortes entre-temps.
func _forget_dead() -> void:
	var alive: Array[Node3D] = []
	for mob in _spawned:
		if is_instance_valid(mob):
			alive.append(mob)
	_spawned = alive


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group(player_group)
	return players[0] as Node3D if not players.is_empty() else null
