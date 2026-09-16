class_name StateMachine
extends Node

## Machine à états simple, pilotant ses nœuds [State] enfants.
##
## Un seul état est actif à la fois. Les transitions se font par nom de nœud,
## ce qui permet de composer un comportement en ajoutant ou retirant des états
## dans la scène, sans toucher au code de la machine. Le mouton et le zombie
## partagent ainsi la même mécanique, avec des états différents.

## Émis à chaque changement d'état.
signal state_changed(state_name: StringName)

## Nom du nœud enfant par lequel commencer.
@export var initial_state: StringName = &"Idle"

## État actuellement actif, ou null avant le premier démarrage.
var current_state: State


func _ready() -> void:
	for child in get_children():
		if child is State:
			(child as State).state_machine = self

	# Différé : les composants frères (santé, navigation) doivent être prêts.
	travel.call_deferred(initial_state)


func _physics_process(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


## Bascule vers l'état portant le nom de nœud [param state_name].
func travel(state_name: StringName) -> void:
	var next := get_node_or_null(NodePath(String(state_name))) as State

	if next == null:
		push_warning("StateMachine : état '%s' introuvable." % state_name)
		return

	if next == current_state:
		return

	if current_state != null:
		current_state.exit()

	current_state = next
	current_state.enter()
	state_changed.emit(state_name)


## Nom de l'état actif, ou une chaîne vide.
func get_current_state_name() -> StringName:
	return current_state.name if current_state != null else &""
