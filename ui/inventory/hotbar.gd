class_name Hotbar
extends Control

## Barre rapide : les premiers emplacements de l'inventaire, toujours visibles.
##
## Réutilise le même [ItemSlotUI] que la grille d'inventaire, donc le
## glisser-déposer y fonctionne de la même façon. La sélection se fait aux
## touches 1 à 6 ou à la molette.

const SLOT_SCENE: PackedScene = preload("res://ui/inventory/item_slot_ui.tscn")

## Émis quand l'emplacement actif change.
signal selection_changed(index: int, stack: ItemStack)

## Chemin vers le composant [Inventory] dont on affiche les premiers emplacements.
@export var inventory_path: NodePath
## Nombre d'emplacements affichés dans la barre.
@export var slot_count: int = 6

@onready var _row: HBoxContainer = $Row

var _inventory: Inventory
var _slot_uis: Array[ItemSlotUI] = []
var _selected_index: int = 0


func _ready() -> void:
	_inventory = get_node_or_null(inventory_path) as Inventory
	if _inventory == null:
		push_warning("Hotbar : aucun Inventory trouvé à '%s'." % inventory_path)
		return

	_build_slots()
	_inventory.changed.connect(_refresh)
	_refresh()
	_apply_selection()


func _unhandled_input(event: InputEvent) -> void:
	if UiState.is_any_open():
		return

	for index in slot_count:
		if event.is_action_pressed("hotbar_%d" % (index + 1)):
			select(index)
			return

	if event.is_action_pressed("hotbar_next"):
		select(wrapi(_selected_index + 1, 0, _slot_uis.size()))
	elif event.is_action_pressed("hotbar_previous"):
		select(wrapi(_selected_index - 1, 0, _slot_uis.size()))


## Sélectionne l'emplacement [param index] de la barre.
func select(index: int) -> void:
	if index < 0 or index >= _slot_uis.size() or index == _selected_index:
		return

	_selected_index = index
	_apply_selection()


## Pile actuellement sélectionnée, ou null.
func get_selected_stack() -> ItemStack:
	if _inventory == null or _selected_index >= _inventory.slots.size():
		return null
	return _inventory.slots[_selected_index]


func _build_slots() -> void:
	for child in _row.get_children():
		child.queue_free()
	_slot_uis.clear()

	var count := mini(slot_count, _inventory.slots.size())
	for index in count:
		var slot_ui := SLOT_SCENE.instantiate() as ItemSlotUI
		slot_ui.slot_index = index
		slot_ui.drop_requested.connect(_on_drop_requested)
		_row.add_child(slot_ui)
		_slot_uis.append(slot_ui)


func _refresh() -> void:
	for index in _slot_uis.size():
		_slot_uis[index].display(_inventory.slots[index])

	# Le contenu de l'emplacement actif a pu changer sous nos pieds.
	selection_changed.emit(_selected_index, get_selected_stack())


func _apply_selection() -> void:
	for index in _slot_uis.size():
		_slot_uis[index].set_selected(index == _selected_index)

	selection_changed.emit(_selected_index, get_selected_stack())


func _on_drop_requested(from_index: int, to_index: int) -> void:
	_inventory.move_slot(from_index, to_index)
