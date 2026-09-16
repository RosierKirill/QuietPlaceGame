class_name RecipeIngredient
extends Resource

## Un ingrédient d'une [Recipe] : un objet et la quantité consommée.

## Objet requis.
@export var item: Item
## Quantité consommée par fabrication.
@export_range(1, 999) var quantity: int = 1
