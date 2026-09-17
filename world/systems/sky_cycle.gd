class_name SkyCycle
extends Node3D

## Pilote le soleil, le ciel et la lumière ambiante selon l'heure du jeu.
##
## À poser dans un niveau, avec le soleil et l'environnement en enfants ou
## désignés par chemin. Ne décide pas de l'heure : il ne fait que traduire
## celle de l'horloge en éclairage.

@export_group("Nœuds pilotés")
## Lumière directionnelle jouant le rôle du soleil.
@export var sun_path: NodePath
## WorldEnvironment dont on ajuste le ciel et l'ambiance.
@export var environment_path: NodePath

@export_group("Couleurs")
## Couleur du soleil au zénith.
@export var day_color: Color = Color(1.0, 0.97, 0.9)
## Couleur du soleil rasant, au lever et au coucher.
@export var horizon_color: Color = Color(1.0, 0.65, 0.38)
## Couleur de la lune, la nuit.
@export var night_color: Color = Color(0.45, 0.55, 0.78)

@export_group("Intensités")
## Intensité du soleil en plein jour.
@export var day_energy: float = 1.0
## Intensité de la lune, la nuit. Volontairement basse : il doit faire sombre.
@export var night_energy: float = 0.06
## Luminosité ambiante de jour.
@export var day_ambient: float = 1.0
## Luminosité ambiante de nuit.
@export var night_ambient: float = 0.12

@onready var _sun: DirectionalLight3D = get_node_or_null(sun_path) as DirectionalLight3D
@onready var _environment: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment


func _ready() -> void:
	if _sun == null:
		push_warning("SkyCycle : aucun soleil trouvé à '%s'." % sun_path)
	_apply(TimeOfDay.time_of_day)


func _process(_delta: float) -> void:
	_apply(TimeOfDay.time_of_day)


## Traduit [param hour] en orientation, couleur et intensité.
func _apply(hour: float) -> void:
	if _sun == null:
		return

	# Le soleil fait un tour complet par jour ; midi le place au zénith.
	var sun_angle := deg_to_rad((hour / 24.0) * 360.0 - 90.0)
	_sun.rotation = Vector3(sun_angle, deg_to_rad(-35.0), 0.0)

	# Hauteur du soleil au-dessus de l'horizon, de -1 (minuit) à 1 (midi).
	var elevation := sin(sun_angle)

	if elevation <= 0.0:
		# Nuit : lumière lunaire, faible et froide.
		_sun.light_color = night_color
		_sun.light_energy = night_energy
		_set_ambient(night_ambient)
		return

	# Jour : la teinte passe de l'orange rasant au blanc de midi.
	var height_ratio := clampf(elevation, 0.0, 1.0)
	var warmth := clampf(height_ratio * 2.5, 0.0, 1.0)

	_sun.light_color = horizon_color.lerp(day_color, warmth)
	_sun.light_energy = lerpf(night_energy, day_energy, height_ratio)
	_set_ambient(lerpf(night_ambient, day_ambient, height_ratio))


func _set_ambient(value: float) -> void:
	if _environment == null or _environment.environment == null:
		return

	_environment.environment.ambient_light_energy = value
	_environment.environment.background_energy_multiplier = maxf(value, 0.05)
