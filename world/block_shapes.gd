class_name BlockShapes
extends RefCounted
## Catalogue des formes de bloc (GAME-1223, affiné GAME-1225).
##
## Un bloc fait BLOCK_SIZE (0.75 unité) et se découpe en 3 x 3 x 3 sous-voxels
## de 0.25 sur LES TROIS AXES. Une forme dit, pour chaque colonne (lx, lz) du
## bloc, quels sous-voxels sont pleins — les états sont donc « déduits des
## sous-voxels », et le mailleur lisse se charge du biseau.
##
## 21 états pleins + le vide :
##   - PLEIN
##   - 6 PLATS : dalle d'UN sous-voxel (0.25) contre chacune des 6 faces
##   - 6 DEMIS : dalle de DEUX sous-voxels (0.5) contre chacune des 6 faces
##   - 4 PENTES DE SOL : le dessus descend vers l'est, l'ouest, le nord, le sud
##   - 4 PENTES DE PLAFOND : le dessous remonte vers ces mêmes directions
##
## Les pentes sont PARAMÉTRÉES : `high` et `low` donnent l'épaisseur, en
## sous-voxels (0 à 3), au bord haut et au bord bas de la pente. Une pente peut
## donc suivre le dénivelé réel du voisin — 0.25, 0.5 ou 0.75 — au lieu de
## toujours descendre d'un bloc entier. Les valeurs par défaut (3 → 1)
## reproduisent l'ancienne pente pleine.
##
## Repères : X = est, Z = sud, Y = haut. lx, ly, lz vont de 0 à 2.

enum {
	VIDE,
	PLEIN,
	PLAT_BAS,     # dalle 0.25 contre la face -Y
	PLAT_HAUT,    # dalle 0.25 contre la face +Y
	PLAT_OUEST,   # dalle 0.25 contre la face -X
	PLAT_EST,     # dalle 0.25 contre la face +X
	PLAT_NORD,    # dalle 0.25 contre la face -Z
	PLAT_SUD,     # dalle 0.25 contre la face +Z
	DEMI_BAS,     # dalle 0.5 contre la face -Y
	DEMI_HAUT,    # dalle 0.5 contre la face +Y
	DEMI_OUEST,   # dalle 0.5 contre la face -X
	DEMI_EST,     # dalle 0.5 contre la face +X
	DEMI_NORD,    # dalle 0.5 contre la face -Z
	DEMI_SUD,     # dalle 0.5 contre la face +Z
	PENTE_EST,    # sol qui descend vers +X
	PENTE_OUEST,  # sol qui descend vers -X
	PENTE_NORD,   # sol qui descend vers -Z
	PENTE_SUD,    # sol qui descend vers +Z
	PLAFOND_EST,  # plafond qui remonte vers +X
	PLAFOND_OUEST,
	PLAFOND_NORD,
	PLAFOND_SUD,
}

const NAMES := [
	"vide", "plein",
	"plat bas", "plat haut", "plat ouest", "plat est", "plat nord", "plat sud",
	"demi bas", "demi haut", "demi ouest", "demi est", "demi nord", "demi sud",
	"pente est", "pente ouest", "pente nord", "pente sud",
	"plafond est", "plafond ouest", "plafond nord", "plafond sud",
]

const N := 3
const EMPTY := Vector2i(0, -1)   # intervalle vide


## Épaisseur (en sous-voxels) d'une pente à la tranche `i`, de 0 au bord haut à
## N - 1 au bord bas. Interpolation linéaire arrondie au sous-voxel.
static func ramp_height(high: int, low: int, i: int) -> int:
	var h := float(high) - float(high - low) * float(i) / float(N - 1)
	return clampi(int(floor(h + 0.5)), 0, N)


## Intervalle [début, fin] des sous-voxels pleins sur la colonne (lx, lz) de ce
## bloc. Renvoie EMPTY si la colonne est vide. Un seul intervalle par colonne :
## toutes les formes du catalogue sont d'un seul tenant verticalement, ce qui
## permet de remplir le terrain par tranches plutôt que voxel par voxel.
##
## `high` et `low` ne servent qu'aux pentes (voir ramp_height).
static func column_range(state: int, lx: int, lz: int, high: int = N, low: int = 1) -> Vector2i:
	match state:
		PLEIN:
			return Vector2i(0, N - 1)
		PLAT_BAS:
			return Vector2i(0, 0)
		DEMI_BAS:
			return Vector2i(0, 1)
		PLAT_HAUT:
			return Vector2i(N - 1, N - 1)
		DEMI_HAUT:
			return Vector2i(N - 2, N - 1)
		PLAT_OUEST:
			return Vector2i(0, N - 1) if lx == 0 else EMPTY
		DEMI_OUEST:
			return Vector2i(0, N - 1) if lx <= 1 else EMPTY
		PLAT_EST:
			return Vector2i(0, N - 1) if lx == N - 1 else EMPTY
		DEMI_EST:
			return Vector2i(0, N - 1) if lx >= N - 2 else EMPTY
		PLAT_NORD:
			return Vector2i(0, N - 1) if lz == 0 else EMPTY
		DEMI_NORD:
			return Vector2i(0, N - 1) if lz <= 1 else EMPTY
		PLAT_SUD:
			return Vector2i(0, N - 1) if lz == N - 1 else EMPTY
		DEMI_SUD:
			return Vector2i(0, N - 1) if lz >= N - 2 else EMPTY
		PENTE_EST:
			return _floor_span(ramp_height(high, low, lx))
		PENTE_OUEST:
			return _floor_span(ramp_height(high, low, N - 1 - lx))
		PENTE_NORD:
			return _floor_span(ramp_height(high, low, N - 1 - lz))
		PENTE_SUD:
			return _floor_span(ramp_height(high, low, lz))
		PLAFOND_EST:
			return _ceiling_span(ramp_height(high, low, lx))
		PLAFOND_OUEST:
			return _ceiling_span(ramp_height(high, low, N - 1 - lx))
		PLAFOND_NORD:
			return _ceiling_span(ramp_height(high, low, N - 1 - lz))
		PLAFOND_SUD:
			return _ceiling_span(ramp_height(high, low, lz))
	return EMPTY


static func _floor_span(height: int) -> Vector2i:
	return Vector2i(0, height - 1) if height > 0 else EMPTY


static func _ceiling_span(height: int) -> Vector2i:
	return Vector2i(N - height, N - 1) if height > 0 else EMPTY


## Dalle posée au sol d'une épaisseur donnée en sous-voxels : 0 → vide,
## 1 → plat bas (0.25), 2 → demi bas (0.5), 3 → plein (0.75).
static func flat_state(height: int) -> int:
	match clampi(height, 0, N):
		1:
			return PLAT_BAS
		2:
			return DEMI_BAS
		3:
			return PLEIN
	return VIDE


## Dalle collée au plafond d'une épaisseur donnée : 1 → plat haut, 2 → demi
## haut, 3 → plein.
static func ceiling_flat_state(height: int) -> int:
	match clampi(height, 0, N):
		1:
			return PLAT_HAUT
		2:
			return DEMI_HAUT
		3:
			return PLEIN
	return VIDE


## Dalle de 0.25 contre une face latérale (0 = est, 1 = ouest, 2 = nord, 3 = sud).
static func thin_slab(direction: int) -> int:
	return [PLAT_EST, PLAT_OUEST, PLAT_NORD, PLAT_SUD][direction]


## Dalle de 0.5 contre une face latérale, mêmes indices.
static func half_slab(direction: int) -> int:
	return [DEMI_EST, DEMI_OUEST, DEMI_NORD, DEMI_SUD][direction]


## Pente de sol qui descend vers cette direction (0 = est, 1 = ouest,
## 2 = nord, 3 = sud).
static func floor_slope(direction: int) -> int:
	return [PENTE_EST, PENTE_OUEST, PENTE_NORD, PENTE_SUD][direction]


## Pente de plafond qui remonte vers cette direction, mêmes indices.
static func ceiling_slope(direction: int) -> int:
	return [PLAFOND_EST, PLAFOND_OUEST, PLAFOND_NORD, PLAFOND_SUD][direction]


## Décalage (en blocs) de la direction : 0 = est, 1 = ouest, 2 = nord, 3 = sud.
static func direction_offset(direction: int) -> Vector2i:
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)][direction]
