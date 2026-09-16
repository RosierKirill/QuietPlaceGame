class_name ItemStack
extends Resource

## Une pile d'objets occupant un emplacement d'inventaire.
##
## Une pile vide est représentée par [code]item == null[/code].

## Objet empilé, ou null si l'emplacement est vide.
@export var item: Item
## Nombre d'exemplaires. Toujours 0 quand [member item] est null.
@export var quantity: int = 0


## Construit une pile. Sert de raccourci au code appelant.
static func create(stack_item: Item, stack_quantity: int = 1) -> ItemStack:
	var stack := ItemStack.new()
	stack.item = stack_item
	stack.quantity = stack_quantity
	return stack


func is_empty() -> bool:
	return item == null or quantity <= 0


## Place restante avant que la pile soit pleine.
func free_space() -> int:
	if is_empty():
		return 0
	return maxi(item.max_stack - quantity, 0)


## Vrai si [param other] contient le même objet, donc fusionnable avec cette pile.
func matches(other: ItemStack) -> bool:
	if is_empty() or other == null or other.is_empty():
		return false
	return item.id == other.item.id


## Vide la pile.
func clear() -> void:
	item = null
	quantity = 0


## Copie indépendante de la pile.
func duplicate_stack() -> ItemStack:
	return ItemStack.create(item, quantity)
