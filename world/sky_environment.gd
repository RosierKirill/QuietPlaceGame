class_name SkyEnvironment
extends Node3D
## Ciel, soleil et nuages, pilotés par l'horloge du monde (GAME-1235, GAME-1236).
##
## Ce nœud possède la lumière directionnelle et l'environnement : il est le seul
## endroit qui décide de la couleur du ciel et de la position du soleil. Il lit
## TimeOfDay et n'écrit rien dedans, comme les autres abonnés de l'horloge.
##
## La nuit, la même lumière devient la lune : même arc, côté opposé, froide et
## faible. Une seule lumière directionnelle suffit et le ciel reste cohérent.

const SKY_SHADER := preload("res://world/shaders/sky.gdshader")

@export_group("Soleil")
## Puissance de la lumière au zénith.
@export var sun_energy: float = 1.15
## Puissance de la lune.
@export var moon_energy: float = 0.10
## Couleur du soleil haut dans le ciel.
@export var sun_high_color: Color = Color(1.0, 0.97, 0.92)
## Couleur du soleil rasant, au lever et au coucher.
@export var sun_low_color: Color = Color(1.0, 0.63, 0.35)
## Couleur de la lune.
@export var moon_color: Color = Color(0.62, 0.72, 0.95)
## Inclinaison de l'arc du soleil : 0 = il passe par le zénith.
@export_range(0.0, 0.9) var sun_tilt: float = 0.35

@export_group("Ciel")
@export var horizon_day: Color = Color(0.72, 0.84, 0.96)
@export var horizon_sunset: Color = Color(0.95, 0.66, 0.42)
@export var ambient_day: float = 0.5
@export var ambient_night: float = 0.12

@export_group("Nuages")
@export_range(0.0, 1.0) var cloud_coverage: float = 0.42

var _sun: DirectionalLight3D
var _sky_material: ShaderMaterial
var _environment: Environment


func _ready() -> void:
	_build()
	_update()


func _process(_delta: float) -> void:
	_update()


## Lumière directionnelle du monde, pour qui en a besoin (ombres, pousse…).
func sun() -> DirectionalLight3D:
	return _sun


func _build() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	add_child(_sun)

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	_sky_material.set_shader_parameter("cloud_coverage", cloud_coverage)
	var sky := Sky.new()
	sky.sky_material = _sky_material
	# Le ciel n'a pas besoin d'être rafraîchi à chaque image en pleine
	# résolution : les nuages dérivent lentement.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = _environment
	add_child(world_env)


func _update() -> void:
	var hour := 12.0
	var sunrise := 6.0
	var sunset := 20.0
	var clock := get_node_or_null("/root/TimeOfDay")
	if clock != null:
		hour = clock.time_of_day
		sunrise = clock.sunrise_hour
		sunset = clock.sunset_hour

	# Position du soleil sur son arc : 0 au lever à l'est, 1 au coucher à
	# l'ouest. La nuit, la lune parcourt le même arc.
	var is_day := hour >= sunrise and hour < sunset
	var progress := 0.0
	if is_day:
		progress = (hour - sunrise) / maxf(sunset - sunrise, 0.001)
	else:
		var night_length := 24.0 - sunset + sunrise
		var since_sunset := hour - sunset if hour >= sunset else hour + 24.0 - sunset
		progress = since_sunset / maxf(night_length, 0.001)

	var angle := PI * progress
	var body := Vector3(cos(angle), sin(angle), sun_tilt).normalized()
	var light_direction := -body
	_sun.global_transform = Transform3D(
		Basis.looking_at(light_direction, Vector3.UP), Vector3.ZERO)

	# Le jour s'installe quand le soleil dépasse l'horizon, et le crépuscule
	# dure le temps qu'il monte un peu.
	var height := body.y if is_day else -1.0
	var day_factor := smoothstep(-0.06, 0.18, height)
	# Rasant = chaud ; haut = blanc.
	var warmth := smoothstep(0.0, 0.35, maxf(height, 0.0))
	var sun_tint := sun_low_color.lerp(sun_high_color, warmth)

	if is_day:
		_sun.light_color = sun_tint
		_sun.light_energy = sun_energy * maxf(day_factor, 0.05)
	else:
		_sun.light_color = moon_color
		_sun.light_energy = moon_energy
	_sun.shadow_enabled = is_day and day_factor > 0.05

	var horizon := horizon_sunset.lerp(horizon_day, warmth)
	_sky_material.set_shader_parameter("sun_direction", light_direction)
	_sky_material.set_shader_parameter("sun_color",
		Vector3(sun_tint.r, sun_tint.g, sun_tint.b))
	_sky_material.set_shader_parameter("day_factor", day_factor)
	_sky_material.set_shader_parameter("horizon_day",
		Vector3(horizon.r, horizon.g, horizon.b))
	_environment.ambient_light_energy = lerpf(ambient_night, ambient_day, day_factor)
