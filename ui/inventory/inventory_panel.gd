class_name InventoryPanel
extends Control

## Panneau d'inventaire : grille d'emplacements ouverte par la touche Inventaire.
##
## Construit un [ItemSlotUI] par emplacement du modèle, puis redessine la grille
## à chaque signal [signal Inventory.changed]. Toute action de l'utilisateur est
## traduite en appel au modèle, jamais appliquée directement à l'affichage.

const SLOT_SCENE: PackedScene = preload("res://ui/inventory/item_slot_ui.tscn")

## Chemin vers le composant [Inventory] à afficher.
@export var inventory_path: NodePath
## Nombre d'emplacements par ligne.
@export var columns: int = 6

@onready var _grid: GridContainer = $Background/Margin/Content/Grid

## Modèle affiché.
var _inventory: Inventory
## Emplacements affichés, dans le même ordre que ceux du modèle.
var _slot_uis: Array[ItemSlotUI] = []


func _ready() -> void:
	hide()

	_inventory = get_node_or_null(inventory_path) as Inventory
	if _inventory == null:
		push_warning("InventoryPanel : aucun Inventory trouvé à '%s'." % inventory_path)
		return

	_grid.columns = columns
	_build_slots()
	_inventory.changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Ouvre ou ferme le panneau.
func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	show()
	UiState.push_ui()


func close() -> void:
	if not visible:
		return
	hide()
	UiState.pop_ui()


## Crée un emplacement affiché par emplacement du modèle.
func _build_slots() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_slot_uis.clear()

	for index in _inventory.slots.size():
		var slot_ui := SLOT_SCENE.instantiate() as ItemSlotUI
		slot_ui.slot_index = index
		slot_ui.drop_requested.connect(_on_drop_requested)
		slot_ui.split_requested.connect(_on_split_requested)
		_grid.add_child(slot_ui)
		_slot_uis.append(slot_ui)


## Redessine tous les emplacements à partir du modèle.
func _refresh() -> void:
	for index in _slot_uis.size():
		_slot_uis[index].display(_inventory.slots[index])


func _on_drop_requested(from_index: int, to_index: int) -> void:
	_inventory.move_slot(from_index, to_index)


func _on_split_requested(index: int) -> void:
	_inventory.split_slot(index)
