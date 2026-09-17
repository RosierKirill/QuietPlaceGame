class_name DeathBag
extends StaticBody3D

## Sac laissé au point de mort, contenant ce que portait le joueur.
##
## N'a aucune logique de stockage propre : c'est le composant [Inventory],
## exactement comme un coffre. Disparaît une fois vidé, pour ne pas joncher
## le monde de sacs vides.

@onready var inventory: Inventory = $Inventory
@onready var _interactable: Interactable = $Interactable


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	inventory.changed.connect(_on_inventory_changed)


## Déverse le contenu de [param source] dans le sac.
func fill_from(source: Inventory) -> void:
	if source == null:
		return

	for index in source.slots.size():
		source.transfer_slot_to(index, inventory)


func _on_interacted(interactor: Node3D) -> void:
	var hud := UiNodes.find_hud(interactor)
	var player_inventory := UiNodes.find_inventory(interactor)

	if hud == null or player_inventory == null:
		return

	hud.open_container(inventory, player_inventory)


## Un sac vide n'a plus de raison d'être.
func _on_inventory_changed() -> void:
	for stack in inventory.slots:
		if not stack.is_empty():
			return

	queue_free()
