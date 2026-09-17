extends Node

## Sauvegarde et chargement de la partie.
##
## Autoload. Ne connaît aucun système de jeu : il parcourt les nœuds du groupe
## « saveable », demande à chacun ses données, et les lui rend au chargement.
## Ajouter un système sauvegardable ne demande donc aucune modification ici —
## c'est ce qui permettra à la faim, à la soif et au terrain voxel de s'y
## brancher plus tard sans toucher à ce fichier.
##
## Un nœud sauvegardable appartient au groupe « saveable » et expose :
##   func get_save_id() -> String
##   func save_data() -> Dictionary
##   func load_data(data: Dictionary) -> void

## Émis après une sauvegarde réussie.
signal game_saved
## Émis après un chargement réussi.
signal game_loaded
## Émis quand une opération échoue, avec la raison.
signal save_failed(reason: String)

## Version du format. À incrémenter si la structure change, pour pouvoir
## refuser proprement une sauvegarde devenue incompatible.
const FORMAT_VERSION: int = 1
const SAVE_PATH: String = "user://savegame.json"
const SAVEABLE_GROUP: StringName = &"saveable"

## Intervalle de la sauvegarde automatique, en secondes. 0 la désactive.
var autosave_interval: float = 300.0
## Recharge automatiquement la partie au lancement, si une sauvegarde existe.
var load_on_start: bool = true
## Sauvegarde automatiquement à la fermeture du jeu.
var save_on_quit: bool = true

var _autosave_timer: float = 0.0


func _ready() -> void:
	# On intercepte la fermeture pour avoir le temps d'écrire avant de quitter.
	get_tree().set_auto_accept_quit(false)

	if load_on_start and has_save():
		# Le tour de boucle laisse la scène principale finir de se construire :
		# sans lui, le joueur et le monde n'existent pas encore. Pas de
		# rechargement ici : la scène vient justement d'être créée.
		await get_tree().process_frame
		load_game(false)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return

	if save_on_quit:
		save_game()

	get_tree().quit()


func _process(delta: float) -> void:
	if autosave_interval <= 0.0:
		return

	_autosave_timer += delta
	if _autosave_timer >= autosave_interval:
		_autosave_timer = 0.0
		save_game()


## Écrit la partie sur disque. Retourne false en cas d'échec.
func save_game() -> bool:
	var entries := {}

	for node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not _is_saveable(node):
			push_warning("SaveManager : '%s' est dans le groupe mais incomplet." % node)
			continue

		entries[node.call("get_save_id")] = node.call("save_data")

	var payload := {
		"format_version": FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"time_of_day": TimeOfDay.time_of_day,
		"day": TimeOfDay.day,
		"entries": entries,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		save_failed.emit("Écriture impossible : %s" % FileAccess.get_open_error())
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	_autosave_timer = 0.0
	game_saved.emit()
	return true


## Recharge la partie depuis le disque.
##
## Reconstruit d'abord la scène, puis y applique les données. Sans ce
## rechargement, on appliquerait la sauvegarde par-dessus l'état courant : les
## créatures tuées et les ressources abattues resteraient absentes, puisque
## rien ne les remettrait dans l'arbre.
##
## [param reload_scene] à false uniquement au lancement, où la scène est neuve.
func load_game(reload_scene: bool = true) -> bool:
	var payload := _read_save()
	if payload.is_empty():
		return false

	if reload_scene:
		get_tree().reload_current_scene()
		# Deux tours : le premier effectue l'échange de scène, le second laisse
		# les _ready() de la nouvelle scène s'exécuter.
		await get_tree().process_frame
		await get_tree().process_frame

	_apply_payload(payload)
	game_loaded.emit()
	return true


## Lit et valide le fichier. Retourne un dictionnaire vide en cas d'échec.
func _read_save() -> Dictionary:
	if not has_save():
		save_failed.emit("Aucune sauvegarde trouvée.")
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		save_failed.emit("Lecture impossible : %s" % FileAccess.get_open_error())
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not parsed is Dictionary:
		save_failed.emit("Fichier de sauvegarde illisible.")
		return {}

	var payload := parsed as Dictionary

	# On refuse plutôt que de charger n'importe comment une version inconnue.
	if int(payload.get("format_version", 0)) != FORMAT_VERSION:
		save_failed.emit("Sauvegarde d'une version incompatible.")
		return {}

	return payload


## Redistribue les données aux nœuds sauvegardables de la scène courante.
func _apply_payload(payload: Dictionary) -> void:
	TimeOfDay.set_time(
		float(payload.get("time_of_day", 8.0)),
		int(payload.get("day", 1))
	)

	var entries: Dictionary = payload.get("entries", {})
	for node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
		if not _is_saveable(node):
			continue

		var id: String = node.call("get_save_id")
		if entries.has(id):
			node.call("load_data", entries[id])


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Supprime la sauvegarde. Sert à repartir de zéro.
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func _is_saveable(node: Node) -> bool:
	return (
		node.has_method("get_save_id")
		and node.has_method("save_data")
		and node.has_method("load_data")
	)
