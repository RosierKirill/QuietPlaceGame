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
## Accélération au sol. Plus la valeur est haute, plus la prise en main est sèche.
@export var acceleration: float = 12.0
## Freinage appliqué quand aucune direction n'est demandée.
@export var friction: float = 14.0

@export_group("Caméra")
## Sensibilité de la souris (radians par pixel de déplacement).
@export var mouse_sensitivity: float = 0.002
## Angle vertical maximal, en degrés, vers le haut comme vers le bas.
@export var pitch_limit_degrees: float = 89.0

@onready var _camera_pivot: Node3D = $CameraPivot

## Gravité du projet, lue une seule fois au chargement.
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	_set_mouse_captured(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _is_mouse_captured():
		_rotate_view(event.relative)
	elif event.is_action_pressed("ui_cancel"):
		# Échap libère le curseur ; un clic dans la fenêtre le recapture.
		_set_mouse_captured(not _is_mouse_captured())
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
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

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


func _set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	)


func _is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
