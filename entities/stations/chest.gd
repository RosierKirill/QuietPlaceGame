class_name Chest
extends StaticBody3D

## Coffre : un second inventaire, ouvert face à celui du joueur.
##
## Réutilise le composant [Inventory] du joueur sans modification — un coffre
## n'est rien d'autre qu'un inventaire posé dans le monde.

@onready var inventory: Inventory = $Inventory
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(interactor: Node3D) -> void:
	var hud := UiNodes.find_hud(interactor)
	var player_inventory := UiNodes.find_inventory(interactor)

	if hud == null or player_inventory == null:
		push_warning("Chest : interface ou inventaire introuvable sur l'interacteur.")
		return

	hud.open_container(inventory, player_inventory)
