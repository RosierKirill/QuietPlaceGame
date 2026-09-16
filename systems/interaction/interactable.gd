class_name Interactable
extends Node3D

## Composant rendant interactif le corps physique parent.
##
## À ajouter comme enfant direct d'un StaticBody3D / RigidBody3D / CharacterBody3D.
## Le rayon d'interaction du joueur le détecte, affiche [member prompt] à l'écran,
## et appelle [method interact] quand le joueur presse la touche d'interaction.

## Émis quand le joueur interagit avec cet objet.
signal interacted(interactor: Node3D)

## Texte affiché à l'écran quand le joueur vise cet objet.
@export var prompt: String = "Interagir"
## Si faux, l'objet est ignoré par le rayon d'interaction.
@export var enabled: bool = true


## Déclenche l'interaction. [param interactor] est le nœud à l'origine de l'action.
func interact(interactor: Node3D) -> void:
	if enabled:
		interacted.emit(interactor)
