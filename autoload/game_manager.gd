extends Node

## Navigation entre l'écran titre et la partie, et mise en pause.
##
## Autoload. Centralise l'ordre des opérations — changer de scène, attendre
## qu'elle soit construite, puis appliquer la sauvegarde — pour qu'aucun écran
## n'ait à connaître ni le chemin des scènes ni cet enchaînement.

## Émis quand le jeu se met en pause ou en sort.
signal pause_changed(is_paused: bool)

const MAIN_MENU_SCENE: String = "res://ui/main_menu.tscn"
const GAME_SCENE: String = "res://world/demo.tscn"


## Démarre une partie neuve. La sauvegarde existante est effacée.
func start_new_game() -> void:
	set_paused(false)
	SaveManager.delete_save()
	get_tree().change_scene_to_file(GAME_SCENE)


## Reprend la partie sauvegardée.
func continue_game() -> void:
	set_paused(false)
	get_tree().change_scene_to_file(GAME_SCENE)

	# Deux tours : le premier effectue le changement de scène, le second laisse
	# les _ready() s'exécuter avant qu'on y injecte les données.
	await get_tree().process_frame
	await get_tree().process_frame

	SaveManager.load_game(false)


## Revient à l'écran titre.
func return_to_menu() -> void:
	set_paused(false)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Met le jeu en pause ou le reprend. Le curseur suit l'état des interfaces.
func set_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return

	get_tree().paused = paused
	pause_changed.emit(paused)


func is_paused() -> bool:
	return get_tree().paused


func quit_game() -> void:
	# On repasse par la notification de fermeture, qui déclenche la sauvegarde.
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
