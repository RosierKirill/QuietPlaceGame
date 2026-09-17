class_name PlayerController
extends CharacterBody3D

## Contrôleur du joueur à la première personne.
##
## Gère le déplacement horizontal, la gravité, la rotation de la vue à la souris
## et la capture du curseur. Le lacet (gauche/droite) tourne le corps entier ;
## le tangage (haut/bas) ne tourne que le pivot de caméra, afin que la direction
## de déplacement reste toujours horizontale.

@export_group("Déplacement")
## Vitesse de marche, en mètres par seconde.
@export var walk_speed: float = 5.0
## Vitesse en sprint, en mètres par seconde.
@export var sprint_speed: float = 8.0
## Vitesse verticale communiquée au saut, en mètres par seconde.
@export var jump_velocity: float = 4.5
## Énergie consommée par seconde de sprint.
@export var sprint_energy_per_second: float = 20.0
## Accélération au sol. Plus la valeur est haute, plus la prise en main est sèche.
@export var acceleration: float = 12.0
## Freinage appliqué quand aucune direction n'est demandée.
@export var friction: float = 14.0

@export_group("Mort")
## Scène du sac déposé au point de mort.
@export var death_bag_scene: PackedScene = preload("res://entities/items/death_bag.tscn")
## Si vrai, l'inventaire est vidé dans un sac à la mort.
@export var drop_inventory_on_death: bool = true

@export_group("Caméra")
## Sensibilité de la souris (radians par pixel de déplacement).
@export var mouse_sensitivity: float = 0.002
## Angle vertical maximal, en degrés, vers le haut comme vers le bas.
@export var pitch_limit_degrees: float = 89.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _health: Health = $Health
@onready var _energy: Energy = $Energy
@onready var _inventory: Inventory = $Inventory
@onready var _need_effects: NeedEffects = $NeedEffects
@onready var _hud: Hud = $Hud

## Transform de départ, point de réapparition par défaut.
var _spawn_transform: Transform3D

## Gravité du projet, lue une seule fois au chargement.
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	_set_mouse_captured(true)
	_spawn_transform = global_transform
	add_to_group(&"saveable")
	_health.died.connect(_on_died)
	_hud.respawn_requested.connect(respawn)


func _unhandled_input(event: InputEvent) -> void:
	# Quand une interface est ouverte, elle a la main sur la souris.
	if UiState.is_any_open():
		return

	# Échap appartient désormais au menu pause : le curseur suit l'état des
	# interfaces, il n'a plus à être basculé à la main ici.
	if event is InputEventMouseMotion and _is_mouse_captured():
		_rotate_view(event.relative)
	elif event is InputEventMouseButton and event.pressed and not _is_mouse_captured():
		_set_mouse_captured(true)


func _physics_process(delta: float) -> void:
	_handle_jump()
	_apply_gravity(delta)
	_apply_horizontal_movement(delta)
	move_and_slide()


## Déclenche un saut si la touche est pressée et que le joueur touche le sol.
func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


# --- Contrat de sauvegarde ---

func get_save_id() -> String:
	return "player"


## Enregistre la position, l'orientation et les jauges. Tout composant enfant
## exposant save_data() est inclus automatiquement, ce qui couvrira la faim et
## la soif sans modifier ce code.
func save_data() -> Dictionary:
	var components := {}

	for child in get_children():
		if child.has_method("save_data") and child.has_method("get_save_id"):
			continue  # Sauvegardé pour son propre compte, via le groupe.
		if child is Health:
			components["health"] = (child as Health).current_health
		elif child is Energy:
			components["energy"] = (child as Energy).current_energy

	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"pitch": _camera_pivot.rotation.x,
		"components": components,
	}


func load_data(data: Dictionary) -> void:
	var position_values: Array = data.get("position", [])
	if position_values.size() == 3:
		global_position = Vector3(position_values[0], position_values[1], position_values[2])

	rotation.y = float(data.get("yaw", 0.0))
	_camera_pivot.rotation.x = float(data.get("pitch", 0.0))
	velocity = Vector3.ZERO

	var components: Dictionary = data.get("components", {})
	if components.has("health"):
		_health.current_health = float(components["health"])
		_health.health_changed.emit(_health.current_health, _health.max_health)
	if components.has("energy"):
		_energy.current_energy = float(components["energy"])
		_energy.energy_changed.emit(_energy.current_energy, _energy.max_energy)

	set_physics_process(not _health.is_dead())


## Applique la gravité tant que le joueur n'est pas au sol.
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta


## Calcule la vitesse horizontale à partir des entrées de déplacement.
func _apply_horizontal_movement(delta: float) -> void:
	var input_direction := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	# La direction est exprimée dans le repère du joueur : sa rotation de lacet
	# détermine où est "devant".
	var direction := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var target_speed := walk_speed

	# On ne sprinte que si le joueur avance ET qu'il reste de l'énergie à payer.
	# Affamé ou assoiffé, on ne court plus : l'effort demande des réserves.
	var can_sprint := not _need_effects.has_critical_need()
	var wants_sprint := (
		can_sprint
		and Input.is_action_pressed("sprint")
		and not direction.is_zero_approx()
	)
	if wants_sprint and _energy.try_consume(sprint_energy_per_second * delta):
		target_speed = sprint_speed

	if direction.is_zero_approx():
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, friction * delta)
	else:
		horizontal_velocity = horizontal_velocity.move_toward(
			direction * target_speed, acceleration * delta
		)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z


## Tourne la vue : lacet sur le corps, tangage sur le pivot de caméra.
func _rotate_view(mouse_delta: Vector2) -> void:
	rotate_y(-mouse_delta.x * mouse_sensitivity)

	var pitch_limit := deg_to_rad(pitch_limit_degrees)
	_camera_pivot.rotation.x = clampf(
		_camera_pivot.rotation.x - mouse_delta.y * mouse_sensitivity,
		-pitch_limit,
		pitch_limit
	)


## Réaction à la mort : le butin tombe, les commandes sont coupées,
## l'écran de mort prend la main.
func _on_died() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO

	if drop_inventory_on_death:
		_drop_inventory()

	_hud.show_death()


## Dépose le contenu de l'inventaire dans un sac, au point de mort.
## Ne crée aucun sac si le joueur ne portait rien.
func _drop_inventory() -> void:
	if death_bag_scene == null or _inventory == null:
		return

	if not _has_any_item():
		return

	var bag := death_bag_scene.instantiate() as DeathBag
	get_parent().add_child(bag)
	bag.global_position = global_position
	bag.fill_from(_inventory)


func _has_any_item() -> bool:
	for stack in _inventory.slots:
		if not stack.is_empty():
			return true
	return false


## Remet le joueur en jeu : retour au point d'apparition, jauges restaurées.
## Tout composant portant une méthode restore() est réinitialisé, ce qui
## couvrira la faim et la soif sans modifier ce code.
func respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_camera_pivot.rotation.x = 0.0

	_health.restore()
	_energy.restore()

	for child in get_children():
		if child.has_method("restore") and child != _health and child != _energy:
			child.call("restore")

	set_physics_process(true)
	_set_mouse_captured(true)


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func _is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
