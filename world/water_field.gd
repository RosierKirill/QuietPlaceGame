class_name WaterField
extends RefCounted
## Nappe d'eau du monde : UNE HAUTEUR PAR COLONNE DE BLOCS (GAME-1232).
##
## Choix assumé : 2.5D. Une colonne porte une seule nappe, ce qui couvre la mer,
## les lacs, les canaux creusés et l'écoulement de proche en proche. Une grotte
## qui passe sous un lac ne peut pas être inondée séparément. Le jour où ce sera
## un vrai besoin, une implémentation 3D prendra la place de celle-ci derrière
## la même interface : ground_at, surface_at, set_surface, ground_changed, step.
##
## Deux régimes cohabitent :
##   - la MER, qui n'est pas stockée : toute colonne dont le sol est sous le
##     niveau de la mer en est, point. Réservoir infini, donc un canal creusé
##     depuis la côte se remplit sans fin et ne vide pas l'océan.
##   - les colonnes MODIFIÉES, qui sortent de la règle et gardent leur propre
##     niveau : c'est là que l'écoulement travaille.
##
## L'écoulement ne tourne que sur les colonnes réveillées (creusement, arrivée
## d'eau). Un monde au repos ne coûte rien.

const PTG := preload("res://world/procedural_terrain_generator.gd")

## Marqueur « pas d'eau dans cette colonne ».
const DRY := -1.0e9
## En sous-voxels : en dessous, deux colonnes sont considérées à niveau.
const EPSILON := 0.01
## Part de l'écart transférée à chaque pas. Plus haut = plus nerveux, mais
## l'eau oscille entre deux colonnes au lieu de se poser.
const TRANSFER := 0.45

var _generator                      # WorldGenerator
var _sea: float                     # niveau de la mer, en sous-voxels
var _levels: Dictionary = {}        # Vector2i -> float : colonnes hors règle
var _raw: Dictionary = {}           # Vector2i -> float : hauteurs brutes
var _ground: Dictionary = {}        # Vector2i -> float : cache du sol lissé
var _active: Dictionary = {}        # Vector2i -> true : colonnes à faire couler
var _dirty: Dictionary = {}         # Vector2i -> true : colonnes à remailler

const OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _init(generator) -> void:
	_generator = generator
	_sea = PTG.SEA_LEVEL / PTG.VOXEL_SIZE


## Niveau de la mer, en sous-voxels.
func sea_level() -> float:
	return _sea


# --- Lecture ------------------------------------------------------------------

## Altitude du sol de cette colonne, en sous-voxels — la même hauteur lissée
## que celle dont le générateur tire le terrain.
##
## Deux caches : les hauteurs brutes, partagées entre voisines (le lissage en
## lit neuf par colonne, sans cache on paierait neuf fois le bruit), et le
## résultat lissé.
func ground_at(bx: int, bz: int) -> float:
	var key := Vector2i(bx, bz)
	var g = _ground.get(key)
	if g != null:
		return g
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var near := Vector2i(bx + dx, bz + dz)
			if not _raw.has(near):
				_raw[near] = _generator.column_height(near.x, near.y)
	g = _generator.smoothed_height(bx, bz, _raw)
	_ground[key] = g
	return g


## Altitude de la surface de l'eau, en sous-voxels, ou DRY s'il n'y a pas d'eau.
func surface_at(bx: int, bz: int) -> float:
	var lv = _levels.get(Vector2i(bx, bz))
	if lv != null:
		return lv
	return _sea if ground_at(bx, bz) < _sea else DRY


## Hauteur d'eau au-dessus du sol, en sous-voxels (0 si à sec).
func depth_at(bx: int, bz: int) -> float:
	var s := surface_at(bx, bz)
	if s == DRY:
		return 0.0
	return maxf(s - ground_at(bx, bz), 0.0)


## Cette colonne est-elle de la mer libre ? La mer est un réservoir infini :
## elle alimente sans se vider et absorbe sans monter.
func is_ocean(bx: int, bz: int) -> bool:
	return not _levels.has(Vector2i(bx, bz)) and ground_at(bx, bz) < _sea


# --- Écriture -----------------------------------------------------------------

## Impose un niveau à une colonne (DRY pour l'assécher) et la réveille.
func set_surface(bx: int, bz: int, level: float) -> void:
	_levels[Vector2i(bx, bz)] = level
	_mark(bx, bz)
	wake(bx, bz)


## À appeler quand le terrain d'une colonne a changé, avec la NOUVELLE altitude
## du sol : le générateur ne connaît pas les modifications du joueur, c'est donc
## à l'appelant de la mesurer sur le terrain réel.
##
## La colonne sort au passage de la règle de la mer et garde le niveau qu'elle
## avait, sinon un trou creusé sous le niveau de la mer se remplirait tout seul
## sans être relié à quoi que ce soit.
func ground_changed(bx: int, bz: int, new_ground: float) -> void:
	var key := Vector2i(bx, bz)
	var before := surface_at(bx, bz)
	_ground[key] = new_ground
	if not _levels.has(key):
		_levels[key] = before
	elif before != DRY and before < new_ground:
		_levels[key] = DRY          # on a rebouché au-dessus de l'eau
	_mark(bx, bz)
	wake(bx, bz)


## Réveille une colonne et ses voisines pour l'écoulement.
func wake(bx: int, bz: int) -> void:
	_active[Vector2i(bx, bz)] = true
	for offset in OFFSETS:
		_active[Vector2i(bx + offset.x, bz + offset.y)] = true


func _mark(bx: int, bz: int) -> void:
	_dirty[Vector2i(bx, bz)] = true


## Colonnes dont la nappe a bougé depuis le dernier appel. Le maillage les
## relit puis vide la liste.
func take_dirty() -> Array:
	var out := _dirty.keys()
	_dirty.clear()
	return out


func active_count() -> int:
	return _active.size()


# --- Écoulement ---------------------------------------------------------------

## Fait couler au plus `budget` colonnes. Retourne le nombre traité.
func step(budget: int) -> int:
	if _active.is_empty():
		return 0
	var keys := _active.keys()
	var done := 0
	for key in keys:
		if done >= budget:
			break
		_active.erase(key)
		done += 1
		_flow(key.x, key.y)
	return done


## Égalise une colonne avec ses quatre voisines. L'eau descend vers les plus
## basses et monte depuis les plus hautes ; la mer, elle, ne bouge jamais.
func _flow(bx: int, bz: int) -> void:
	if is_ocean(bx, bz):
		return                      # réservoir infini : rien à faire
	var ground := ground_at(bx, bz)
	var surface := surface_at(bx, bz)
	var level := ground if surface == DRY else surface
	var moved := false

	for offset in OFFSETS:
		var nx := bx + offset.x
		var nz := bz + offset.y
		var n_ground := ground_at(nx, nz)
		var n_surface := surface_at(nx, nz)
		var n_level := n_ground if n_surface == DRY else n_surface
		var gap := level - n_level

		if gap > EPSILON:
			# On donne : jamais plus que l'eau réellement présente, et jamais
			# au point de passer sous le sol du voisin.
			var give: float = minf(gap * TRANSFER, maxf(level - ground, 0.0))
			if give <= EPSILON:
				continue
			level -= give
			moved = true
			if not is_ocean(nx, nz):
				_levels[Vector2i(nx, nz)] = n_level + give
				_mark(nx, nz)
				wake(nx, nz)
			# Vers la mer, l'eau disparaît : l'océan ne monte pas.
		elif gap < -EPSILON and not is_ocean(nx, nz):
			# On reçoit d'une voisine plus haute, si elle a de quoi donner.
			var take: float = minf(-gap * TRANSFER, maxf(n_level - n_ground, 0.0))
			if take <= EPSILON:
				continue
			level += take
			moved = true
			_levels[Vector2i(nx, nz)] = n_level - take
			_mark(nx, nz)
			wake(nx, nz)
		elif gap < -EPSILON:
			# Voisine océan : elle alimente sans se vider.
			level += -gap * TRANSFER
			moved = true

	if not moved:
		return
	# Une pellicule sous le seuil n'est plus de l'eau : on assèche, sinon des
	# colonnes restent réveillées pour un millième de sous-voxel.
	if level - ground <= EPSILON:
		_levels[Vector2i(bx, bz)] = DRY
	else:
		_levels[Vector2i(bx, bz)] = level
	_mark(bx, bz)
	wake(bx, bz)
