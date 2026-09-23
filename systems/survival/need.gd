class_name Need
extends Node

## Besoin vital qui décroît avec le temps : faim, soif, et ce qui suivra.
##
## Générique comme [Health] : la faim et la soif ne sont pas deux scripts mais
## deux instances de celui-ci, réglées différemment. Ajouter la température ou
## la fatigue ne demandera pas une ligne de code.
##
## Se sauvegarde lui-même via le groupe « saveable », sans que le gestionnaire
## de sauvegarde ait à le connaître.

## Émis à chaque variation.
signal need_changed(current: float, maximum: float)
## Émis au passage sous le seuil critique.
signal became_critical
## Émis quand le besoin atteint zéro.
signal depleted

## Identifiant utilisé par les objets consommables pour désigner ce besoin.
@export var id: StringName = &""
## Nom affiché dans l'interface.
@export var display_name: String = "Besoin"
## Valeur maximale, aussi utilisée comme valeur de départ.
@export var max_value: float = 100.0
## Perte par seconde.
@export var decay_per_second: float = 0.5
## Part en dessous de laquelle le besoin devient critique, de 0.0 à 1.0.
@export_range(0.0, 1.0) var critical_ratio: float = 0.2
## Identifiant de sauvegarde. Laissé vide, le besoin n'est pas sauvegardé.
@export var save_id: String = ""

## Valeur courante.
var current_value: float

var _was_critical: bool = false


func _ready() -> void:
	current_value = max_value

	if save_id != "":
		add_to_group(&"saveable")

	need_changed.emit(current_value, max_value)


func _process(delta: float) -> void:
	if decay_per_second <= 0.0 or is_depleted():
		return

	_set_value(current_value - decay_per_second * delta)


## Remonte le besoin de [param amount], sans dépasser le maximum.
func fill(amount: float) -> void:
	if amount <= 0.0:
		return

	_set_value(current_value + amount)


## Fait baisser le besoin de [param amount]. Pendant que [fill] sert à ce qui
## restaure, celui-ci sert à ce qui consomme ponctuellement — le souffle sous
## l'eau, par exemple — sans passer par la décroissance automatique.
func drain(amount: float) -> void:
	if amount <= 0.0:
		return

	_set_value(current_value - amount)


## Remet le besoin au maximum. Appelé à la réapparition.
func restore() -> void:
	_was_critical = false
	_set_value(max_value)


func get_ratio() -> float:
	return current_value / max_value if max_value > 0.0 else 0.0


func is_critical() -> bool:
	return get_ratio() <= critical_ratio


func is_depleted() -> bool:
	return current_value <= 0.0


func _set_value(value: float) -> void:
	var clamped := clampf(value, 0.0, max_value)
	if is_equal_approx(clamped, current_value):
		return

	current_value = clamped
	need_changed.emit(current_value, max_value)

	# Le signal critique ne part qu'au franchissement, pas à chaque image.
	var critical_now := is_critical()
	if critical_now and not _was_critical:
		became_critical.emit()
	_was_critical = critical_now

	if is_depleted():
		depleted.emit()


# --- Contrat de sauvegarde ---

func get_save_id() -> String:
	return save_id


func save_data() -> Dictionary:
	return {"value": current_value}


func load_data(data: Dictionary) -> void:
	_was_critical = false
	_set_value(float(data.get("value", max_value)))
