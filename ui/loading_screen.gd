class_name LoadingScreen
extends CanvasLayer
## Écran de chargement affiché pendant la génération du monde (GAME-1220).
##
## Le joueur n'apparaît jamais devant un terrain vide : la scène de terrain
## laisse cet écran par-dessus tout tant que le chunk de spawn n'est pas généré
## ET que sa collision n'est pas prête. La graine du monde est affichée pour
## pouvoir rejouer la même carte.
##
## Les nœuds sont cherchés à l'usage (et pas avec @onready) : la scène peut
## recevoir des appels dès l'instanciation, avant son entrée dans l'arbre.

const ROOT_PATH := "Root"
const BAR_PATH := "Root/Center/Box/Bar"
const STATUS_PATH := "Root/Center/Box/Status"
const SEED_PATH := "Root/Center/Box/SeedLabel"

var _progress := 0.0
var _pending_seed := -1
var _pending_status := ""


func _ready() -> void:
	set_progress(_progress)
	if _pending_seed >= 0:
		show_seed(_pending_seed)
	if _pending_status != "":
		set_status(_pending_status)


## Graine affichée en bas de l'écran.
func show_seed(seed_value: int) -> void:
	_pending_seed = seed_value
	var label := get_node_or_null(SEED_PATH) as Label
	if label != null:
		label.text = "Graine : %d" % seed_value


## Avancement entre 0 et 1. La barre ne recule jamais.
func set_progress(value: float) -> void:
	_progress = maxf(_progress, clampf(value, 0.0, 1.0))
	var bar := get_node_or_null(BAR_PATH) as ProgressBar
	if bar != null:
		bar.value = _progress * 100.0


## Ligne d'état (« Génération du terrain… », « Mise en place de la collision… »).
func set_status(text: String) -> void:
	_pending_status = text
	var label := get_node_or_null(STATUS_PATH) as Label
	if label != null:
		label.text = text


## Termine le chargement : barre pleine, puis fondu et disparition.
func finish() -> void:
	set_progress(1.0)
	set_status("Prêt")
	var root := get_node_or_null(ROOT_PATH) as Control
	if root == null or not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
