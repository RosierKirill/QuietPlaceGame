class_name ItemSlotUI
extends Panel

## Emplacement d'inventaire affiché à l'écran.
##
## Affiche une pile et sert de source comme de cible au glisser-déposer.
## Ne modifie jamais l'inventaire lui-même : il remonte l'intention via
## [signal drop_requested], que le panneau traduit en appel au modèle.

## Émis quand une pile est lâchée sur cet emplacement.
signal drop_requested(from_index: int, to_index: int)
## Émis sur clic droit, pour scinder la pile en deux.
signal split_requested(index: int)

## Position de cet emplacement dans l'inventaire.
@export var slot_index: int = 0

@onready var _icon: TextureRect = $Icon
@onready var _quantity_label: Label = $Quantity

## Pile actuellement affichée, ou null.
var _stack: ItemStack


## Met l'affichage à jour à partir de [param stack].
func display(stack: ItemStack) -> void:
	_stack = stack

	if stack == null or stack.is_empty():
		_icon.texture = null
		_quantity_label.text = ""
		tooltip_text = ""
		return

	_icon.texture = stack.item.icon
	_quantity_label.text = str(stack.quantity) if stack.quantity > 1 else ""
	tooltip_text = "%s\n%s" % [stack.item.display_name, stack.item.description]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			split_requested.emit(slot_index)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if _stack == null or _stack.is_empty():
		return null

	var preview := TextureRect.new()
	preview.texture = _stack.item.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(48, 48)
	preview.size = Vector2(48, 48)
	set_drag_preview(preview)

	return {"source_index": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("source_index")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_requested.emit(int((data as Dictionary)["source_index"]), slot_index)
