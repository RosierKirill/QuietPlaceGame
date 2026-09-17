class_name WorldState
extends Node

## Mémorise ce que le joueur a changé dans le monde.
##
## Deux choses seulement : les ressources déjà récoltées, qui ne doivent pas
## réapparaître, et les objets laissés au sol.
##
## Les créatures ne sont volontairement pas sauvegardées. Comme le chargement
## reconstruit la scène, celles posées à la main y reviennent intactes : un
## rechargement remet donc les zombies en jeu, ce qui est le comportement
## attendu d'un monde vivant.
##
## NE SAUVEGARDE PAS LE TERRAIN : avec le passage au voxel, la persistance du
## terrain sera assurée nativement par VoxelStreamSQLite.

const WORLD_ITEM_SCENE: PackedScene = preload("res://entities/items/world_item.tscn")

## Identifiant de sauvegarde.
@export var save_id: String = "world"

## Chemins des ressources récoltées, relatifs à la racine du niveau.
var _harvested: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")
	_watch_existing_harvestables()


## S'abonne à chaque ressource récoltable déjà présente dans le niveau.
func _watch_existing_harvestables() -> void:
	for node in _find_all_harvestables(get_parent()):
		var path := String(get_parent().get_path_to(node))
		node.harvested.connect(_on_harvested.bind(path))


func _find_all_harvestables(root: Node) -> Array[Harvestable]:
	var found: Array[Harvestable] = []

	for child in root.get_children():
		if child is Harvestable:
			found.append(child as Harvestable)
		found.append_array(_find_all_harvestables(child))

	return found


func _on_harvested(path: String) -> void:
	_harvested[path] = true


# --- Contrat de sauvegarde ---

func get_save_id() -> String:
	return save_id


func save_data() -> Dictionary:
	var ground_items := []

	for item in _find_all_world_items(get_parent()):
		if item.item == null:
			continue

		ground_items.append({
			"item": String(item.item.id),
			"quantity": item.quantity,
			"position": [
				item.global_position.x, item.global_position.y, item.global_position.z
			],
		})

	return {
		"harvested": _harvested.keys(),
		"ground_items": ground_items,
	}


func load_data(data: Dictionary) -> void:
	_harvested.clear()

	# Retirer les ressources qui avaient déjà été récoltées.
	for path in data.get("harvested", []):
		_harvested[path] = true
		var node := get_parent().get_node_or_null(NodePath(path))
		if node != null:
			node.queue_free()

	# Repartir d'un sol propre, puis replacer ce qui y était.
	for item in _find_all_world_items(get_parent()):
		item.queue_free()

	for entry in data.get("ground_items", []):
		_restore_ground_item(entry)


func _restore_ground_item(entry: Dictionary) -> void:
	var item := ItemDatabase.get_item(StringName(entry.get("item", "")))
	if item == null:
		return

	var position_values: Array = entry.get("position", [])
	if position_values.size() != 3:
		return

	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	world_item.item = item
	world_item.quantity = int(entry.get("quantity", 1))
	get_parent().add_child(world_item)
	world_item.global_position = Vector3(
		position_values[0], position_values[1], position_values[2]
	)


func _find_all_world_items(root: Node) -> Array[WorldItem]:
	var found: Array[WorldItem] = []

	for child in root.get_children():
		if child is WorldItem:
			found.append(child as WorldItem)
		found.append_array(_find_all_world_items(child))

	return found
