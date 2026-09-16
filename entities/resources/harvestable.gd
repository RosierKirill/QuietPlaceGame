class_name Harvestable
extends StaticBody3D

## Ressource récoltable : arbre, rocher, veine de minerai.
##
## Encaisse les coups via sa [Hurtbox] et, une fois ses points de vie épuisés,
## dépose son butin au sol sous forme de [WorldItem] avant de disparaître.
## Le butin passe donc par le ramassage normal, sans code dédié.

## Émis juste avant la disparition, une fois le butin déposé.
signal harvested

## Objet lâché à l'épuisement des points de vie.
@export var drop_item: Item
## Quantité minimale lâchée.
@export var drop_minimum: int = 1
## Quantité maximale lâchée.
@export var drop_maximum: int = 3
## Rayon, en mètres, dans lequel le butin est dispersé autour de la ressource.
@export var drop_spread: float = 0.6

## Scène utilisée pour matérialiser le butin au sol.
const WORLD_ITEM_SCENE: PackedScene = preload("res://entities/items/world_item.tscn")

@onready var _health: Health = $Health


func _ready() -> void:
	_health.died.connect(_on_died)


func _on_died() -> void:
	_spawn_drops()
	harvested.emit()
	queue_free()


## Dépose le butin au sol, légèrement dispersé autour de la ressource.
func _spawn_drops() -> void:
	if drop_item == null:
		return

	var quantity := randi_range(drop_minimum, drop_maximum)
	if quantity <= 0:
		return

	var drop := WORLD_ITEM_SCENE.instantiate() as WorldItem
	drop.item = drop_item
	drop.quantity = quantity

	# Ajouté au parent, sinon il disparaîtrait avec la ressource.
	get_parent().add_child(drop)
	drop.global_position = global_position + _random_offset()


## Décalage horizontal aléatoire, pour que le butin ne surgisse pas au centre exact.
func _random_offset() -> Vector3:
	var angle := randf() * TAU
	var distance := randf() * drop_spread
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
