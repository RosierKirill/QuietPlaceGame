class_name State
extends Node

## Un état d'une [StateMachine].
##
## Classe de base à hériter. Chaque état est un nœud enfant de la machine, et
## son nom de nœud sert d'identifiant pour les transitions.

## Machine qui pilote cet état. Renseignée automatiquement au démarrage.
var state_machine: StateMachine


## Appelé une fois à l'entrée dans l'état.
func enter() -> void:
	pass


## Appelé une fois à la sortie de l'état.
func exit() -> void:
	pass


## Appelé à chaque pas de physique tant que l'état est actif.
func physics_update(_delta: float) -> void:
	pass


## Raccourci vers [method StateMachine.travel].
func travel(state_name: StringName) -> void:
	if state_machine != null:
		state_machine.travel(state_name)
