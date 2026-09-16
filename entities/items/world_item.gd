class_name WorldItem
extends StaticBody3D

## Objet posé au sol, ramassable par le joueur.
##
## Affiche l'icône de l'objet en panneau tourné vers la caméra et se supprime
## dès que tout son contenu est entré dans l'inventaire. Si l'inventaire est
## plein, la quantité restante demeure au sol.

## Objet contenu. Sans lui, l'entité ne sert à rien.
@export var item: Item
## Nombre d'exemplaires posés au sol.
@export var quantity: int = 1

@onready var _interactable: Interactable = $Interactable
@onready var _sprite: Sprite3D = $Sprite3D


func _ready() -> void:
	_interactable.interacted.connect(_on_interacted)
	_refresh()


## Met à jour l'icône affichée et le texte d'invite.
func _refresh() -> void:
	if item == null:
		_interactable.prompt = "Ramasser"
		return

	_sprite.texture = item.icon
	_interactable.prompt = (
		"Ramasser %s (%d)" % [item.display_name, quantity]
		if quantity > 1
		else "Ramasser %s" % item.display_name
	)


func _on_interacted(interactor: Node3D) -> void:
	var inventory := _find_inventory(interactor)
	if inventory == null:
		push_warning("WorldItem : aucun Inventory sur '%s'." % interactor)
		return

	var left_over := inventory.add_item(item, quantity)

	if left_over <= 0:
		queue_free()
		return

	# Inventaire plein : le reste demeure au sol.
	quantity = left_over
	_refresh()


## Cherche le composant Inventory parmi les enfants directs de [param node].
func _find_inventory(node: Node) -> Inventory:
	if node == null:
		return null

	for child in node.get_children():
		if child is Inventory:
			return child as Inventory

	return null
