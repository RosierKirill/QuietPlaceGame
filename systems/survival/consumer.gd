class_name Consumer
extends Node

## Permet de consommer l'objet sélectionné dans la barre rapide.
##
## Fait le lien entre un objet, qui déclare seulement ce qu'il restaure, et les
## composants [Need] du porteur. Un nouvel aliment ne demande donc aucune ligne
## de code : seulement une ressource avec le bon champ.

## Émis après une consommation réussie.
signal consumed(item: Item)

## Chemin vers la [Hotbar] dont on lit la sélection.
@export var hotbar_path: NodePath

@onready var _inventory: Inventory = _find_inventory()

var _hotbar: Hotbar
var _needs_by_id: Dictionary = {}


func _ready() -> void:
	_hotbar = get_node_or_null(hotbar_path) as Hotbar
	if _hotbar == null:
		push_warning("Consumer : aucune Hotbar trouvée à '%s'." % hotbar_path)

	for child in get_parent().get_children():
		if child is Need and (child as Need).id != &"":
			_needs_by_id[(child as Need).id] = child


func _unhandled_input(event: InputEvent) -> void:
	if UiState.is_any_open() or not event.is_action_pressed("consume"):
		return

	if try_consume_selected():
		get_viewport().set_input_as_handled()


## Consomme l'objet sélectionné s'il est comestible. Retourne false sinon.
func try_consume_selected() -> bool:
	if _hotbar == null or _inventory == null:
		return false

	var stack := _hotbar.get_selected_stack()
	if stack == null or stack.is_empty() or not stack.item.is_consumable():
		return false

	var item := stack.item
	var restored_something := false

	for need_id in item.restores:
		var need := _needs_by_id.get(need_id, null) as Need
		if need == null:
			continue

		need.fill(float(item.restores[need_id]))
		restored_something = true

	if not restored_something:
		return false

	_inventory.remove_item(item, 1)
	consumed.emit(item)
	return true


func _find_inventory() -> Inventory:
	for child in get_parent().get_children():
		if child is Inventory:
			return child as Inventory
	return null
