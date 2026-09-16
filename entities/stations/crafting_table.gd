class_name CraftingTable
extends StaticBody3D

## Table de fabrication : ouvre l'interface de craft avec ses propres recettes.
##
## Les recettes sont portées par la station, pas codées en dur : un four ou une
## forge se feront plus tard en changeant simplement cette liste.

## Recettes proposées par cette station. Tableau de [Recipe].
@export var recipes: Array[Resource] = []

@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(interactor: Node3D) -> void:
	var hud := UiNodes.find_hud(interactor)
	var inventory := UiNodes.find_inventory(interactor)

	if hud == null or inventory == null:
		push_warning("CraftingTable : interface ou inventaire introuvable sur l'interacteur.")
		return

	hud.open_crafting(recipes, inventory)
