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
## Reflète ce que l'interface affiche réellement, indépendamment de _focused.
var _prompt_shown: bool = false


func _ready() -> void:
	if interactor == null:
		interactor = owner as Node3D


func _physics_process(_delta: float) -> void:
	var found := _find_focused_interactable()

	# Une cible détruite entre deux images — objet ramassé, arbre abattu — laisse
	# une référence dont la comparaison n'est pas fiable. On la ramène à null.
	var current: Interactable = _focused if is_instance_valid(_focused) else null

	# On compare aussi l'état réellement affiché : quand la cible est détruite,
	# l'ancienne et la nouvelle valent toutes deux null alors que l'invite est
	# encore à l'écran, et ce seul test permet de la faire disparaître.
	if found == current and _prompt_shown == (found != null):
		return

	_focused = found
	_prompt_shown = found != null
	focus_changed.emit(found)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and is_instance_valid(_focused):
		_focused.interact(interactor)


## Retourne l'Interactable visé par le rayon, ou null s'il n'y en a pas.
func _find_focused_interactable() -> Interactable:
	if not is_colliding():
		return null

	var collider := get_collider()
	if not is_instance_valid(collider) or not collider is Node:
		return null

	for child in (collider as Node).get_children():
		if child is Interactable and (child as Interactable).enabled:
			return child as Interactable

	return null
