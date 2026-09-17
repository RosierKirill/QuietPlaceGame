class_name Health
extends Node

## Composant de points de vie.
##
## Réutilisable tel quel par le joueur, les mobs et les ressources récoltables :
## tout ce qui peut encaisser des dégâts porte ce nœud en enfant.

## Émis à chaque variation des points de vie.
signal health_changed(current: float, maximum: float)
## Émis quand des dégâts sont encaissés. [param source] peut être null.
signal damaged(amount: float, source: Node)
## Émis une seule fois, quand les points de vie atteignent zéro.
signal died

## Points de vie maximum, aussi utilisés comme valeur de départ.
@export var max_health: float = 100.0
## Si vrai, tous les dégâts sont ignorés.
@export var invulnerable: bool = false

## Points de vie courants.
var current_health: float


func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


## Inflige [param amount] dégâts. Sans effet si déjà mort ou invulnérable.
func take_damage(amount: float, source: Node = null) -> void:
	if invulnerable or is_dead() or amount <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(current_health, max_health)

	if is_dead():
		died.emit()


## Rend [param amount] points de vie, sans dépasser le maximum.
func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return

	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


## Remet les points de vie au maximum. Utilisé à la réapparition.
func restore() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


func is_dead() -> bool:
	return current_health <= 0.0
