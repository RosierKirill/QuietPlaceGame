class_name WeaponHolder
extends Node3D

## Porte l'arme tenue en main, à la première personne.
##
## Surveille la barre rapide : l'arme n'apparaît que lorsque l'emplacement
## sélectionné contient l'objet correspondant. L'attaque ouvre brièvement la
## [Hitbox] de l'arme, qui inflige alors des dégâts à tout ce qu'elle traverse
## — ressource récoltable comme créature.

## Émis au déclenchement d'une attaque.
signal attack_started

## Identifiant de l'objet qui matérialise cette arme.
@export var weapon_item_id: StringName = &"dagger"
## Chemin vers la [Hotbar] dont on suit la sélection.
@export var hotbar_path: NodePath
## Durée du mouvement d'attaque, en secondes.
@export var swing_duration: float = 0.24

@onready var _model: Node3D = $DaggerModel
@onready var _hitbox: Hitbox = $DaggerModel/Hitbox

## Vrai quand l'arme est en main.
var _is_equipped: bool = false
## Vrai pendant toute la durée d'un coup, pour empêcher les attaques en rafale.
var _is_attacking: bool = false


func _ready() -> void:
	_set_equipped(false)

	var hotbar := get_node_or_null(hotbar_path) as Hotbar
	if hotbar == null:
		push_warning("WeaponHolder : aucune Hotbar trouvée à '%s'." % hotbar_path)
		return

	hotbar.selection_changed.connect(_on_selection_changed)


func _unhandled_input(event: InputEvent) -> void:
	if UiState.is_any_open():
		return

	if event.is_action_pressed("attack"):
		attack()


## Déclenche un coup, si une arme est en main et qu'aucun coup n'est en cours.
func attack() -> void:
	if not _is_equipped or _is_attacking:
		return

	_is_attacking = true
	attack_started.emit()
	_hitbox.activate()

	# Aller-retour de la lame : la zone de dégâts reste ouverte le temps du geste.
	var tween := create_tween()
	tween.tween_property(_model, "rotation_degrees:x", -70.0, swing_duration * 0.35)
	tween.tween_property(_model, "rotation_degrees:x", 0.0, swing_duration * 0.65)
	await tween.finished

	_hitbox.deactivate()
	_is_attacking = false


## Affiche ou masque l'arme selon l'objet sélectionné dans la barre rapide.
func _on_selection_changed(_index: int, stack: ItemStack) -> void:
	var holds_weapon := (
		stack != null
		and not stack.is_empty()
		and stack.item.id == weapon_item_id
	)
	_set_equipped(holds_weapon)


func _set_equipped(equipped: bool) -> void:
	_is_equipped = equipped
	_model.visible = equipped

	if not equipped:
		_hitbox.deactivate()
		_model.rotation_degrees.x = 0.0
