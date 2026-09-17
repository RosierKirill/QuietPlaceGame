class_name Harvestable
extends StaticBody3D

## Ressource récoltable : arbre, rocher, veine de minerai.
##
## Encaisse les coups via sa [Hurtbox] et, une fois ses points de vie épuisés,
## dépose son butin au sol sous forme de [WorldItem] avant de disparaître.
## Le butin passe donc par le ramassage normal, sans code dédié.

## Émis juste avant la disparition, une fois le butin déposé.
signal harvested

## Délai avant repousse, en secondes. 0 : la ressource disparaît définitivement.
@export var regrow_delay: float = 0.0

@onready var _health: Health = $Health
@onready var _loot: LootTable = get_node_or_null("LootTable") as LootTable


func _ready() -> void:
	_health.died.connect(_on_died)


func _on_died() -> void:
	if _loot != null:
		_loot.drop_at(global_position, get_parent())

	harvested.emit()

	if regrow_delay > 0.0:
		_hide_until_regrown()
	else:
		queue_free()


## Une ressource qui repousse s'efface au lieu de disparaître, puis revient
## avec ses points de vie restaurés. Un buisson à baies se cueille ainsi
## plusieurs fois, contrairement à un arbre qu'on abat.
func _hide_until_regrown() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

	await get_tree().create_timer(regrow_delay).timeout

	if not is_instance_valid(self):
		return

	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_health.restore()
