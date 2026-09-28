class_name TerrainShape
extends RefCounted
## GDScript mirror of the terrain formulas, for point queries.
##
## TerrainGraph generates the world; this class answers "how high is the ground
## here?" for the spawn, the water and the biomes. Every formula below MUST stay
## identical to the one built in TerrainGraph, and both use the same noise
## resources (ProceduralTerrainGenerator.noises()).
##
## All positions are in VOXELS (terrain local space).

const PTG := preload("res://world/procedural_terrain_generator.gd")

var _n: Dictionary


func _init(noise_set: Dictionary) -> void:
	_n = noise_set


## Continuous ground height, in voxels. Same as TerrainGraph._height().
func height_voxels(vx: float, vz: float) -> float:
	var hills: float = _n["hills"].get_noise_2d(vx, vz)
	var mask := smoothstep(PTG.MASK_LOW, PTG.MASK_HIGH, _n["mask"].get_noise_2d(vx, vz))
	var m := clampf(_n["mountain"].get_noise_2d(vx, vz) * 0.5 + 0.5, 0.0, 1.0)
	return PTG.BASE_HEIGHT / PTG.VOXEL_SIZE \
		+ hills * (PTG.HILLS_AMPLITUDE / PTG.VOXEL_SIZE) \
		+ m * m * mask * (PTG.MOUNTAIN_AMPLITUDE / PTG.VOXEL_SIZE)


## Temperature [0, 1]: low-frequency noise, colder with altitude.
func temperature(vx: float, vz: float) -> float:
	var altitude := height_voxels(vx, vz) * PTG.VOXEL_SIZE
	var base: float = _n["temperature"].get_noise_2d(vx, vz) * 0.5 + 0.5
	var cold := maxf(altitude - PTG.COLD_ALTITUDE_START, 0.0) / PTG.COLD_ALTITUDE_RANGE
	return clampf(base - cold, 0.0, 1.0)


## Humidity [0, 1].
func humidity(vx: float, vz: float) -> float:
	return clampf(_n["humidity"].get_noise_2d(vx, vz) * 0.5 + 0.5, 0.0, 1.0)


## 0 = full crust above caves, 1 = open cave entrance.
func entrance_openness(vx: float, vz: float) -> float:
	return smoothstep(PTG.ENTRANCE_LOW, PTG.ENTRANCE_HIGH, _n["entrance"].get_noise_2d(vx, vz))
