class_name Swimmer
extends Node
## Nage, souffle et hydratation au contact de l'eau (GAME-1234).
##
## Composant posé sur le joueur. Il ne connaît que deux choses : le corps qu'il
## fait flotter et la surface d'eau qu'il interroge. Le contrôleur lui laisse la
## main pendant qu'il est dans l'eau, et la reprend dès qu'il en sort.

## Vitesse de nage horizontale.
@export var swim_speed: float = 3.2
## Vitesse de remontée quand le joueur appuie sur saut.
@export var rise_speed: float = 2.8
## Vitesse d'enfoncement au repos, tête sous l'eau.
@export var sink_speed: float = 0.9
## Raideur du rappel vers la surface : plus haut, plus le joueur bouchonne.
@export var buoyancy: float = 3.5
## Freinage de l'eau, en unités par seconde carrée.
@export var water_drag: float = 7.0
## Enfoncement (en unités) à partir duquel on nage au lieu de marcher.
@export var wade_depth: float = 1.0

@export_group("Souffle")
## Perte de souffle par seconde, tête immergée.
@export var breath_drain: float = 7.0
## Reprise du souffle par seconde, une fois à l'air libre.
@export var breath_refill: float = 30.0
## Dégâts par seconde une fois le souffle épuisé.
@export var drown_damage: float = 8.0

@export_group("Boisson")
## Soif rendue par gorgée.
@export var drink_amount: float = 25.0
## Délai entre deux gorgées, en secondes.
@export var drink_cooldown: float = 0.8

var _body: CharacterBody3D
var _head: Node3D
var _health: Health
var _thirst: Need
var _breath: Need
var _water                           # WaterSurface
var _drink_timer: float = 0.0
var _damage_timer: float = 0.0

## Vrai tant que la tête est sous l'eau. Le HUD et les effets peuvent le lire.
var submerged: bool = false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("Swimmer : doit être enfant d'un CharacterBody3D.")
		return
	_head = _body.get_node_or_null("CameraPivot/Camera3D") as Node3D
	_health = _body.get_node_or_null("Health") as Health
	for child in _body.get_children():
		if child is Need:
			match (child as Need).id:
				&"thirst":
					_thirst = child
				&"breath":
					_breath = child


## La surface d'eau est fournie par la scène de terrain, qui la possède.
func set_water(water) -> void:
	_water = water


## Appelé par le contrôleur. Retourne vrai s'il a pris la main sur le corps,
## c'est-à-dire si le joueur nage.
func update(delta: float) -> bool:
	_drink_timer = maxf(_drink_timer - delta, 0.0)
	if _water == null or _body == null:
		return false

	var feet := _body.global_position.y
	var level: float = _water.surface_y(_body.global_position)
	if is_nan(level) or level <= feet:
		_leave_water(delta)
		return false

	var head := _head.global_position.y if _head != null else feet + 1.6
	submerged = level > head
	_breathe(delta)
	_drink()

	# Les pieds mouillés ne suffisent pas : on patauge debout jusqu'à mi-corps.
	if level - feet < wade_depth:
		return false
	_swim(delta, level, head)
	return true


func _leave_water(delta: float) -> void:
	submerged = false
	if _breath != null and _breath.current_value < _breath.max_value:
		_breath.fill(breath_refill * delta)


func _swim(delta: float, level: float, head: float) -> void:
	var velocity := _body.velocity
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (_body.transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if direction.is_zero_approx():
		horizontal = horizontal.move_toward(Vector3.ZERO, water_drag * delta)
	else:
		horizontal = horizontal.move_toward(direction * swim_speed, water_drag * delta)

	var target_y := 0.0
	if Input.is_action_pressed("jump"):
		target_y = rise_speed
	elif submerged:
		target_y = -sink_speed
	else:
		# En surface, on bouchonne : rappel proportionnel à l'écart tête / eau.
		target_y = clampf((level - head) * buoyancy, -sink_speed, rise_speed)
	velocity.y = move_toward(velocity.y, target_y, water_drag * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_body.velocity = velocity


func _breathe(delta: float) -> void:
	if _breath == null:
		return
	if not submerged:
		_breath.fill(breath_refill * delta)
		_damage_timer = 0.0
		return
	_breath.drain(breath_drain * delta)
	if not _breath.is_depleted() or _health == null:
		return
	# Noyade : une salve de dégâts par seconde plutôt qu'un filet continu.
	_damage_timer += delta
	if _damage_timer >= 1.0:
		_damage_timer -= 1.0
		_health.take_damage(drown_damage)


func _drink() -> void:
	if _thirst == null or _drink_timer > 0.0:
		return
	if UiState.is_any_open() or not Input.is_action_just_pressed("interact"):
		return
	if _thirst.current_value >= _thirst.max_value:
		return
	_thirst.fill(drink_amount)
	_drink_timer = drink_cooldown
