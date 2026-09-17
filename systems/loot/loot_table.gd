class_name LootTable
extends Node

## Dépose du butin au sol.
##
## Partagé par les ressources récoltables et les créatures : un arbre abattu et
## une brebis tuée lâchent leur butin par le même chemin. La logique était
## auparavant enfermée dans Harvestable, ce qui aurait obligé à la recopier
## dans les mobs.

const WORLD_ITEM_SCENE: PackedScene = preload("res://entities/items/world_item.tscn")

## Objet lâché.
@export var item: Item
## Quantité minimale.
@export var minimum: int = 1
## Quantité maximale.
@export var maximum: int = 3
## Rayon, en mètres, dans lequel le butin est dispersé.
@export var spread: float = 0.6


## Dépose le butin autour de [param origin], dans [param container].
## Sans conteneur explicite, le butin est ajouté au parent du porteur, faute de
## quoi il disparaîtrait avec lui.
func drop_at(origin: Vector3, container: Node = null) -> void:
	if item == null:
		return

	var quantity := randi_range(minimum, maximum)
	if quantity <= 0:
		return

	var parent := container
	if parent == null:
		parent = get_parent().get_parent() if get_parent() != null else null
	if parent == null:
		return

	var drop := WORLD_ITEM_SCENE.instantiate() as WorldItem
	drop.item = item
	drop.quantity = quantity
	parent.add_child(drop)
	drop.global_position = origin + _random_offset()


func _random_offset() -> Vector3:
	var angle := randf() * TAU
	var distance := randf() * spread
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
