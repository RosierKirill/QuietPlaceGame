class_name BlockShapes
extends RefCounted
## Catalogue des formes de bloc (GAME-1223) — modèle « Terraria en 3D ».
##
## Un bloc fait BLOCK_SIZE (0.75 unité) et se découpe en 3 x 3 x 3 sous-voxels
## de 0.25 sur LES TROIS AXES. Une forme dit, pour chaque colonne (lx, lz) du
## bloc, quels sous-voxels sont pleins — les états sont donc « déduits des
## sous-voxels », et le mailleur lisse se charge du biseau.
##
## 15 états pleins + le vide :
##   - PLEIN
##   - 6 PLATS : une dalle d'un sous-voxel contre chacune des 6 faces du cube
##   - 4 PENTES DE SOL : le dessus descend vers l'est, l'ouest, le nord ou le sud
##   - 4 PENTES DE PLAFOND : le dessous remonte vers l'est, l'ouest, le nord ou
##     le sud (escaliers de plafond des grottes)
##
## Repères : X = est, Z = sud, Y = haut. lx, ly, lz vont de 0 à 2.

enum {
	VIDE,
	PLEIN,
	PLAT_BAS,
	PLAT_HAUT,
	PLAT_OUEST,   # dalle contre la face -X
	PLAT_EST,     # dalle contre la face +X
	PLAT_NORD,    # dalle contre la face -Z
	PLAT_SUD,     # dalle contre la face +Z
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
	"vide", "plein", "plat bas", "plat haut", "plat ouest", "plat est",
	"plat nord", "plat sud", "pente est", "pente ouest", "pente nord",
	"pente sud", "plafond est", "plafond ouest", "plafond nord", "plafond sud",
]

const N := 3
const EMPTY := Vector2i(0, -1)   # intervalle vide


## Intervalle [début, fin] des sous-voxels pleins sur la colonne (lx, lz) de ce
## bloc. Renvoie EMPTY si la colonne est vide. Un seul intervalle par colonne :
## toutes les formes du catalogue sont d'un seul tenant verticalement, ce qui
## permet de remplir le terrain par tranches plutôt que voxel par voxel.
static func column_range(state: int, lx: int, lz: int) -> Vector2i:
	match state:
		PLEIN:
			return Vector2i(0, N - 1)
		PLAT_BAS:
			return Vector2i(0, 0)
		PLAT_HAUT:
			return Vector2i(N - 1, N - 1)
		PLAT_OUEST:
			return Vector2i(0, N - 1) if lx == 0 else EMPTY
		PLAT_EST:
			return Vector2i(0, N - 1) if lx == N - 1 else EMPTY
		PLAT_NORD:
			return Vector2i(0, N - 1) if lz == 0 else EMPTY
		PLAT_SUD:
			return Vector2i(0, N - 1) if lz == N - 1 else EMPTY
		PENTE_EST:
			return Vector2i(0, N - 1 - lx)
		PENTE_OUEST:
			return Vector2i(0, lx)
		PENTE_NORD:
			return Vector2i(0, lz)
		PENTE_SUD:
			return Vector2i(0, N - 1 - lz)
		PLAFOND_EST:
			return Vector2i(lx, N - 1)
		PLAFOND_OUEST:
			return Vector2i(N - 1 - lx, N - 1)
		PLAFOND_NORD:
			return Vector2i(N - 1 - lz, N - 1)
		PLAFOND_SUD:
			return Vector2i(lz, N - 1)
	return EMPTY


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
