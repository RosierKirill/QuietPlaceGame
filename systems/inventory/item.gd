class_name Item
extends Resource

## Définition d'un objet du jeu.
##
## Ressource de données pure, sans logique : chaque objet (bois, pierre, dague…)
## est un fichier .tres dans items/. Ajouter un objet au jeu ne demande donc
## aucun code, seulement une nouvelle ressource.

## Identifiant technique unique, utilisé par les recettes et les sauvegardes.
@export var id: StringName = &""
## Nom affiché dans l'interface.
@export var display_name: String = "Objet"
## Description affichée dans l'interface.
@export_multiline var description: String = ""
## Icône affichée dans les emplacements d'inventaire.
@export var icon: Texture2D
## Nombre maximum d'exemplaires par emplacement. 1 = non empilable.
@export_range(1, 999) var max_stack: int = 99


## Besoins restaurés à la consommation : identifiant du besoin vers la
## quantité rendue. Vide, l'objet n'est pas consommable.
## Exemple : { &"hunger": 25.0 }
@export var restores: Dictionary = {}


## Vrai si l'objet peut être consommé.
func is_consumable() -> bool:
	return not restores.is_empty()


## Vrai si l'objet peut s'empiler dans un même emplacement.
func is_stackable() -> bool:
	return max_stack > 1
