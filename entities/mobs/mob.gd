class_name Mob
extends CharacterBody3D

## Base commune à toutes les créatures.
##
## Porte ce que mouton et zombie ont en commun : points de vie, zone touchable,
## navigation et détection du joueur. Le comportement, lui, vit entièrement
## dans la [StateMachine] de la scène : c'est elle qui décide de fuir ou de
## poursuivre, pas ce script.

## Émis quand la créature meurt, juste avant sa disparition.
signal died

@export_group("Déplacement")
## Vitesse de déplacement normale, en mètres par seconde.
@export var move_speed: float = 2.0
## Vitesse utilisée en poursuite ou en fuite.
@export var alert_speed: float = 4.0
## Vitesse de rotation vers la direction du déplacement.
@export var turn_speed: float = 8.0

@export_group("Perception")
## Distance à laquelle la créature repère le joueur.
@export var detection_radius: float = 12.0
## Distance au-delà de laquelle elle le perd de vue.
@export var lose_target_radius: float = 18.0
## Groupe auquel appartient la cible recherchée.
@export var target_group: StringName = &"player"
## État rejoint quand la créature est blessée. Vide pour ne pas réagir.
@export var hurt_state: StringName = &""

@export_group("Nuit")
## Multiplicateur appliqué au rayon de détection une fois la nuit tombée.
@export var night_detection_multiplier: float = 1.0
## Multiplicateur appliqué à la vitesse d'alerte une fois la nuit tombée.
@export var night_speed_multiplier: float = 1.0

@onready var health: Health = $Health
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

## Cible repérée, ou null.
var target: Node3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _base_detection_radius: float = 0.0
var _base_alert_speed: float = 0.0


func _ready() -> void:
	health.died.connect(_on_died)

	var hurtbox := get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox != null:
		hurtbox.hit_received.connect(_on_hit_received)

	# Valeurs de référence, avant toute majoration nocturne.
	_base_detection_radius = detection_radius
	_base_alert_speed = alert_speed

	TimeOfDay.day_night_changed.connect(_on_day_night_changed)
	_on_day_night_changed(TimeOfDay.is_night())


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	move_and_slide()


## Fixe la destination de navigation.
func set_destination(destination: Vector3) -> void:
	navigation_agent.target_position = destination


## Avance d'un pas le long du chemin calculé, à [param speed].
## Ne fait rien si la destination est atteinte.
func follow_path(delta: float, speed: float) -> void:
	if navigation_agent.is_navigation_finished():
		stop_moving(delta)
		return

	var next_point := navigation_agent.get_next_path_position()
	var direction := (next_point - global_position)
	direction.y = 0.0

	if direction.length_squared() < 0.0001:
		return

	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face_direction(direction, delta)


## Amortit le déplacement horizontal jusqu'à l'arrêt.
func stop_moving(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)


## Cherche la cible la plus proche du groupe surveillé, dans le rayon de détection.
func acquire_target() -> Node3D:
	var candidates := get_tree().get_nodes_in_group(target_group)

	for candidate in candidates:
		if not candidate is Node3D:
			continue

		var node := candidate as Node3D
		if global_position.distance_to(node.global_position) <= detection_radius:
			target = node
			return target

	return null


## Distance à la cible, ou INF s'il n'y en a pas.
func distance_to_target() -> float:
	if target == null:
		return INF
	return global_position.distance_to(target.global_position)


## Vrai si la cible est hors de portée et doit être oubliée.
func has_lost_target() -> bool:
	return target == null or distance_to_target() > lose_target_radius


## Point aléatoire accessible autour de la position actuelle.
func random_point_around(radius: float) -> Vector3:
	var angle := randf() * TAU
	var distance := randf_range(radius * 0.3, radius)
	return global_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)


## Oriente progressivement la créature vers [param direction].
func _face_direction(direction: Vector3, delta: float) -> void:
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, turn_speed * delta)


## La nuit rend certaines créatures plus dangereuses. Les multiplicateurs valant
## 1.0 par défaut, une créature indifférente à la nuit n'a rien à configurer.
func _on_day_night_changed(is_night: bool) -> void:
	if is_night:
		detection_radius = _base_detection_radius * night_detection_multiplier
		alert_speed = _base_alert_speed * night_speed_multiplier
	else:
		detection_radius = _base_detection_radius
		alert_speed = _base_alert_speed


## Un coup encaissé désigne son auteur comme cible et déclenche la réaction
## configurée : fuir pour un mouton, se retourner contre l'agresseur pour un zombie.
func _on_hit_received(_amount: float, source: Node) -> void:
	if hurt_state == &"":
		return

	if source is Node3D:
		target = source as Node3D

	var state_machine := get_node_or_null("StateMachine") as StateMachine
	if state_machine != null:
		state_machine.travel(hurt_state)


func _on_died() -> void:
	var loot := get_node_or_null("LootTable") as LootTable
	if loot != null:
		loot.drop_at(global_position, get_parent())

	died.emit()
	queue_free()
