class_name Recipe
extends Resource

## Recette de fabrication : des ingrédients consommés, un objet produit.
##
## Ressource de données, comme [Item] : ajouter une recette au jeu ne demande
## aucun code, seulement un fichier .tres. La recette sait vérifier et se
## fabriquer elle-même à partir d'un [Inventory], ce qui évite d'éparpiller
## cette logique dans l'interface.

## Identifiant technique unique.
@export var id: StringName = &""
## Nom affiché dans l'interface de fabrication.
@export var display_name: String = "Recette"
## Ingrédients consommés. Tableau de [RecipeIngredient].
@export var ingredients: Array[Resource] = []
## Objet produit.
@export var result_item: Item
## Quantité produite par fabrication.
@export_range(1, 999) var result_quantity: int = 1


## Vrai si [param inventory] contient tous les ingrédients requis.
func can_craft(inventory: Inventory) -> bool:
	if inventory == null or result_item == null or ingredients.is_empty():
		return false

	for entry in ingredients:
		var ingredient := entry as RecipeIngredient
		if ingredient == null or ingredient.item == null:
			return false
		if not inventory.has_item(ingredient.item, ingredient.quantity):
			return false

	return true


## Consomme les ingrédients et produit le résultat dans [param inventory].
## Retourne false si la recette n'est pas réalisable ou si la place manque.
func craft(inventory: Inventory) -> bool:
	if not can_craft(inventory):
		return false

	for entry in ingredients:
		var ingredient := entry as RecipeIngredient
		inventory.remove_item(ingredient.item, ingredient.quantity)

	var left_over := inventory.add_item(result_item, result_quantity)

	# Faute de place, le surplus est perdu : on prévient plutôt que de mentir.
	if left_over > 0:
		push_warning(
			"Recipe '%s' : %d exemplaire(s) perdu(s), inventaire plein." % [id, left_over]
		)

	return true


## Description courte des ingrédients, pour l'interface.
func describe_ingredients() -> String:
	var parts: Array[String] = []

	for entry in ingredients:
		var ingredient := entry as RecipeIngredient
		if ingredient != null and ingredient.item != null:
			parts.append("%s x%d" % [ingredient.item.display_name, ingredient.quantity])

	return ", ".join(parts)
