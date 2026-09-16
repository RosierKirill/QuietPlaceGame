class_name Hud
extends CanvasLayer

## Interface de jeu : viseur, invite d'interaction, barres de vie et d'énergie.
##
## Le HUD ne fait qu'observer : il se connecte aux signaux des composants du
## joueur et ne modifie jamais leur état.

## Chemin vers le [InteractionRay] du joueur, défini dans la scène.
@export var interaction_ray_path: NodePath
## Chemin vers le composant [Health] du joueur.
@export var health_path: NodePath
## Chemin vers le composant [Energy] du joueur.
@export var energy_path: NodePath

@onready var _interaction_prompt: Label = $InteractionPrompt
@onready var _health_bar: ProgressBar = $Bars/HealthBar
@onready var _energy_bar: ProgressBar = $Bars/EnergyBar


func _ready() -> void:
	_interaction_prompt.hide()
	_bind_interaction_ray()
	_bind_health()
	_bind_energy()


func _bind_interaction_ray() -> void:
	var ray := get_node_or_null(interaction_ray_path) as InteractionRay
	if ray == null:
		push_warning("Hud : aucun InteractionRay trouvé à '%s'." % interaction_ray_path)
		return

	ray.focus_changed.connect(_on_focus_changed)


func _bind_health() -> void:
	var health := get_node_or_null(health_path) as Health
	if health == null:
		push_warning("Hud : aucun Health trouvé à '%s'." % health_path)
		return

	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _bind_energy() -> void:
	var energy := get_node_or_null(energy_path) as Energy
	if energy == null:
		push_warning("Hud : aucun Energy trouvé à '%s'." % energy_path)
		return

	energy.energy_changed.connect(_on_energy_changed)
	_on_energy_changed(energy.current_energy, energy.max_energy)


## Affiche ou masque l'invite selon l'objet visé.
func _on_focus_changed(interactable: Interactable) -> void:
	if interactable == null:
		_interaction_prompt.hide()
		return

	_interaction_prompt.text = "[E] %s" % interactable.prompt
	_interaction_prompt.show()


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_energy_changed(current: float, maximum: float) -> void:
	_energy_bar.max_value = maximum
	_energy_bar.value = current
