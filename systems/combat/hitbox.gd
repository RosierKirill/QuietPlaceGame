class_name Hitbox
extends Area3D

## Zone qui inflige des dégâts aux [Hurtbox] qu'elle touche pendant qu'elle
## est active.
##
## Reste inactive au repos et ne s'allume que le temps d'une attaque. Chaque
## cible n'est touchée qu'une fois par passe, afin qu'un coup de dague ne
## compte pas plusieurs fois sur la même image.

## Émis quand une cible est touchée.
signal target_hit(hurtbox: Hurtbox)

## Dégâts infligés par coup.
@export var damage: float = 10.0
## Nœud désigné comme auteur des dégâts. Le propriétaire de la scène par défaut.
@export var source: Node

## Cibles déjà touchées durant la passe en cours.
var _already_hit: Array[Hurtbox] = []


func _ready() -> void:
	monitoring = false

	if source == null:
		source = owner


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return

	for area in get_overlapping_areas():
		if not area is Hurtbox:
			continue

		var hurtbox := area as Hurtbox
		if _already_hit.has(hurtbox):
			continue

		_already_hit.append(hurtbox)
		hurtbox.apply_damage(damage, source)
		target_hit.emit(hurtbox)


## Ouvre une passe d'attaque : la zone devient active et oublie ses cibles.
func activate() -> void:
	_already_hit.clear()
	monitoring = true


## Referme la passe d'attaque.
func deactivate() -> void:
	monitoring = false
	_already_hit.clear()
