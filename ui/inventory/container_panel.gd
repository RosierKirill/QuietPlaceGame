class_name ContainerPanel
extends Control

## Interface d'un conteneur : inventaire du coffre à gauche, celui du joueur
## à droite.
##
## Réutilise les mêmes [ItemSlotUI] que le reste du jeu. Une pile glissée d'une
## grille à l'autre change d'inventaire ; glissée à l'intérieur d'une grille,
## elle s'y déplace simplement — c'est l'étiquette portée par l'emplacement qui
## distingue les deux cas.

const SLOT_SCENE: PackedScene = preload("res://ui/inventory/item_slot_ui.tscn")
const CONTAINER_TAG: StringName = &"container"
const PLAYER_TAG: StringName = &"player"

## Nombre d'emplacements par ligne dans chaque grille.
@export var columns: int = 6

@onready var _container_grid: GridContainer = $Background/Margin/Content/Grids/ContainerSide/Grid
@onready var _player_grid: GridContainer = $Background/Margin/Content/Grids/PlayerSide/Grid

var _container_inventory: Inventory
var _player_inventory: Inventory
var _container_slots: Array[ItemSlotUI] = []
var _player_slots: Array[ItemSlotUI] = []


func _ready() -> void:
	hide()
	_container_grid.columns = columns
	_player_grid.columns = columns


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()


## Ouvre le panneau sur [param container], face à [param player_inventory].
func open_with(container: Inventory, player_inventory: Inventory) -> void:
	_container_inventory = container
	_player_inventory = player_inventory

	_container_slots = _build_grid(_container_grid, container, CONTAINER_TAG)
	_player_slots = _build_grid(_player_grid, player_inventory, PLAYER_TAG)

	if not container.changed.is_connected(_refresh):
		container.changed.connect(_refresh)
	if not player_inventory.changed.is_connected(_refresh):
		player_inventory.changed.connect(_refresh)

	_refresh()
	show()
	UiState.push_ui()


func close() -> void:
	if not visible:
		return

	# Le conteneur a pu être détruit pendant qu'on l'affichait : un sac de mort
	# se supprime dès qu'il est vide. Toute référence est donc à vérifier.
	if is_instance_valid(_container_inventory) and _container_inventory.changed.is_connected(_refresh):
		_container_inventory.changed.disconnect(_refresh)
	if is_instance_valid(_player_inventory) and _player_inventory.changed.is_connected(_refresh):
		_player_inventory.changed.disconnect(_refresh)

	_container_inventory = null
	hide()
	UiState.pop_ui()


## Construit les emplacements affichés d'une grille et retourne la liste obtenue.
func _build_grid(grid: GridContainer, inventory: Inventory, tag: StringName) -> Array[ItemSlotUI]:
	for child in grid.get_children():
		child.queue_free()

	var created: Array[ItemSlotUI] = []
	for index in inventory.slots.size():
		var slot_ui := SLOT_SCENE.instantiate() as ItemSlotUI
		slot_ui.slot_index = index
		slot_ui.inventory_tag = tag
		slot_ui.drop_requested.connect(_on_drop_requested)
		grid.add_child(slot_ui)
		created.append(slot_ui)

	return created


func _refresh() -> void:
	# Si le conteneur a disparu sous nos pieds, on ferme au lieu de lire du vide.
	if not is_instance_valid(_container_inventory) or not is_instance_valid(_player_inventory):
		close()
		return

	for index in mini(_container_slots.size(), _container_inventory.slots.size()):
		_container_slots[index].display(_container_inventory.slots[index])

	for index in mini(_player_slots.size(), _player_inventory.slots.size()):
		_player_slots[index].display(_player_inventory.slots[index])


## Un déplacement au sein d'une grille reste un déplacement ; d'une grille à
## l'autre, c'est un transfert entre inventaires.
func _on_drop_requested(
	from_tag: StringName, from_index: int, to_tag: StringName, _to_index: int
) -> void:
	var source := _inventory_for(from_tag)
	var destination := _inventory_for(to_tag)

	if not is_instance_valid(source) or not is_instance_valid(destination):
		close()
		return

	if from_tag == to_tag:
		source.move_slot(from_index, _to_index)
		return

	source.transfer_slot_to(from_index, destination)


func _inventory_for(tag: StringName) -> Inventory:
	return _container_inventory if tag == CONTAINER_TAG else _player_inventory
