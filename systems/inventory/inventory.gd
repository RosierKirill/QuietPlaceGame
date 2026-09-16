class_name Inventory
extends Node

## Inventaire à emplacements fixes.
##
## Contient uniquement la logique : ajout avec empilement automatique, retrait,
## déplacement et fusion entre emplacements. Aucune dépendance à l'interface,
## qui se contente d'écouter [signal changed]. Le coffre et l'inventaire du
## joueur utilisent tous deux ce même composant.

## Émis dès qu'un emplacement change, avec l'inventaire entier à redessiner.
signal changed
## Émis quand un objet entre dans l'inventaire.
signal item_added(item: Item, quantity: int)

## Nombre d'emplacements.
@export var slot_count: int = 24

## Emplacements, toujours de taille [member slot_count]. Jamais null.
var slots: Array[ItemStack] = []


func _ready() -> void:
	_build_slots()


func _build_slots() -> void:
	slots.clear()
	for i in slot_count:
		slots.append(ItemStack.new())


## Ajoute [param quantity] exemplaires de [param item].
## Retourne la quantité qui n'a pas pu entrer (0 si tout est rentré).
func add_item(item: Item, quantity: int = 1) -> int:
	if item == null or quantity <= 0:
		return quantity

	var remaining := quantity

	# 1. Compléter les piles existantes du même objet.
	if item.is_stackable():
		for stack in slots:
			if remaining <= 0:
				break
			if stack.is_empty() or stack.item.id != item.id:
				continue

			var transferable := mini(stack.free_space(), remaining)
			stack.quantity += transferable
			remaining -= transferable

	# 2. Remplir les emplacements vides.
	for stack in slots:
		if remaining <= 0:
			break
		if not stack.is_empty():
			continue

		var transferable := mini(item.max_stack, remaining)
		stack.item = item
		stack.quantity = transferable
		remaining -= transferable

	if remaining < quantity:
		item_added.emit(item, quantity - remaining)
		changed.emit()

	return remaining


## Retire jusqu'à [param quantity] exemplaires de [param item].
## Retourne la quantité réellement retirée.
func remove_item(item: Item, quantity: int = 1) -> int:
	if item == null or quantity <= 0:
		return 0

	var removed := 0
	for stack in slots:
		if removed >= quantity:
			break
		if stack.is_empty() or stack.item.id != item.id:
			continue

		var taken := mini(stack.quantity, quantity - removed)
		stack.quantity -= taken
		removed += taken
		if stack.quantity <= 0:
			stack.clear()

	if removed > 0:
		changed.emit()

	return removed


## Nombre total d'exemplaires de [param item] présents dans l'inventaire.
func count_item(item: Item) -> int:
	if item == null:
		return 0

	var total := 0
	for stack in slots:
		if not stack.is_empty() and stack.item.id == item.id:
			total += stack.quantity
	return total


## Vrai si l'inventaire contient au moins [param quantity] exemplaires.
func has_item(item: Item, quantity: int = 1) -> bool:
	return count_item(item) >= quantity


## Déplace ou fusionne le contenu de [param from_index] vers [param to_index].
## Si les deux piles contiennent le même objet, elles fusionnent ; sinon, elles
## sont échangées.
func move_slot(from_index: int, to_index: int) -> void:
	if not _is_valid_index(from_index) or not _is_valid_index(to_index):
		return
	if from_index == to_index:
		return

	var source := slots[from_index]
	var target := slots[to_index]

	if source.is_empty():
		return

	if target.matches(source) and source.item.is_stackable():
		var transferable := mini(target.free_space(), source.quantity)
		if transferable > 0:
			target.quantity += transferable
			source.quantity -= transferable
			if source.quantity <= 0:
				source.clear()
			changed.emit()
			return

	slots[from_index] = target
	slots[to_index] = source
	changed.emit()


## Scinde la pile de [param index] en deux, en déposant la moitié dans le
## premier emplacement vide. Sans effet si la pile compte moins de deux objets.
func split_slot(index: int) -> void:
	if not _is_valid_index(index):
		return

	var source := slots[index]
	if source.is_empty() or source.quantity < 2:
		return

	var empty_index := _find_empty_slot()
	if empty_index == -1:
		return

	var moved := source.quantity / 2
	source.quantity -= moved
	slots[empty_index].item = source.item
	slots[empty_index].quantity = moved
	changed.emit()


func _find_empty_slot() -> int:
	for i in slots.size():
		if slots[i].is_empty():
			return i
	return -1


func _is_valid_index(index: int) -> bool:
	return index >= 0 and index < slots.size()
