class_name Hud
extends CanvasLayer

## Interface de jeu : viseur et invite d'interaction.
##
## Écoute le rayon d'interaction du joueur et affiche « [E] <invite> »
## quand un objet interactif est visé.

## Chemin vers le [InteractionRay] du joueur, défini dans la scène.
@export var interaction_ray_path: NodePath

@onready var _interaction_prompt: Label = $InteractionPrompt


func _ready() -> void:
	_interaction_prompt.hide()

	var ray := get_node_or_null(interaction_ray_path) as InteractionRay
	if ray == null:
		push_warning("Hud : aucun InteractionRay trouvé à '%s'." % interaction_ray_path)
		return

	ray.focus_changed.connect(_on_focus_changed)


## Affiche ou masque l'invite selon l'objet visé.
func _on_focus_changed(interactable: Interactable) -> void:
	if interactable == null:
		_interaction_prompt.hide()
		return

	_interaction_prompt.text = "[E] %s" % interactable.prompt
	_interaction_prompt.show()
