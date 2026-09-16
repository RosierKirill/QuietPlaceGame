class_name Hurtbox
extends Area3D

## Zone qui reçoit les dégâts et les transmet à un composant [Health].
##
## C'est la moitié « receveuse » du système de dégâts : un arbre, un rocher,
## un mob ou le joueur portent tous une Hurtbox, et toute [Hitbox] qui la
## touche leur inflige des dégâts sans rien savoir de leur nature.

## Émis à chaque coup encaissé, avant application des dégâts.
signal hit_received(amount: float, source: Node)

## Composant qui encaisse. Résolu automatiquement s'il est laissé vide.
@export var health: Health


func _ready() -> void:
	if health == null:
		health = _find_sibling_health()


## Inflige [param amount] dégâts au [Health] associé.
func apply_damage(amount: float, source: Node = null) -> void:
	hit_received.emit(amount, source)

	if health != null:
		health.take_damage(amount, source)


## Cherche un composant Health parmi les enfants du parent.
func _find_sibling_health() -> Health:
	var parent := get_parent()
	if parent == null:
		return null

	for child in parent.get_children():
		if child is Health:
			return child as Health

	return null
