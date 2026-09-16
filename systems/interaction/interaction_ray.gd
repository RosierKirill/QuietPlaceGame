class_name InteractionRay
extends RayCast3D

## Rayon d'interaction du joueur.
##
## Placé sous la caméra, il détecte en continu le premier [Interactable] visé
## et signale tout changement de cible pour que l'interface affiche l'invite.

## Émis quand l'objet visé change. [param interactable] vaut null si plus rien n'est visé.
signal focus_changed(interactable: Interactable)

## Nœud considéré comme l'auteur de l'interaction (le joueur par défaut).
@export var interactor: Node3D

## Interactable actuellement visé, ou null.
var _focused: Interactable = null


func _ready() -> void:
	if interactor == null:
		interactor = owner as Node3D


func _physics_process(_delta: float) -> void:
	var found := _find_focused_interactable()
	if found != _focused:
		_focused = found
		focus_changed.emit(_focused)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _focused != null:
		_focused.interact(interactor)


## Retourne l'Interactable visé par le rayon, ou null s'il n'y en a pas.
func _find_focused_interactable() -> Interactable:
	if not is_colliding():
		return null

	var collider := get_collider()
	if collider == null or not collider is Node:
		return null

	for child in (collider as Node).get_children():
		if child is Interactable and (child as Interactable).enabled:
			return child as Interactable

	return null
