class_name CraftingPanel
extends Control

## Interface de fabrication, ouverte par une table de craft.
##
## Liste les recettes de la station, marque celles qui sont réalisables selon
## le contenu de l'inventaire, et délègue la fabrication à la recette
## elle-même. La liste se met à jour dès que l'inventaire change.

@onready var _list: VBoxContainer = $Background/Margin/Content/RecipeList

## Recettes proposées par la station ouverte.
var _recipes: Array = []
## Inventaire dans lequel puiser et déposer.
var _inventory: Inventory


func _ready() -> void:
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Ouvre le panneau pour [param recipes], en puisant dans [param inventory].
func open_with(recipes: Array, inventory: Inventory) -> void:
	_recipes = recipes
	_inventory = inventory

	if _inventory != null and not _inventory.changed.is_connected(_refresh):
		_inventory.changed.connect(_refresh)

	_refresh()
	show()
	UiState.push_ui()


func close() -> void:
	if not visible:
		return

	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)

	hide()
	UiState.pop_ui()


## Redessine la liste des recettes et l'état de chacune.
func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	for entry in _recipes:
		var recipe := entry as Recipe
		if recipe == null:
			continue

		_list.add_child(_build_row(recipe))


## Construit la ligne d'une recette : nom, ingrédients, bouton de fabrication.
func _build_row(recipe: Recipe) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s  —  %s" % [recipe.display_name, recipe.describe_ingredients()]
	row.add_child(label)

	var button := Button.new()
	button.text = "Fabriquer"
	button.custom_minimum_size = Vector2(120, 0)

	var craftable := recipe.can_craft(_inventory)
	button.disabled = not craftable
	label.modulate = Color.WHITE if craftable else Color(0.6, 0.6, 0.6)

	button.pressed.connect(_on_craft_pressed.bind(recipe))
	row.add_child(button)

	return row


func _on_craft_pressed(recipe: Recipe) -> void:
	recipe.craft(_inventory)
	_refresh()
