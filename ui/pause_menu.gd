class_name PauseMenu
extends Control

## Menu de pause, ouvert par Échap en cours de partie.
##
## Fige réellement la partie : créatures immobiles, aucun dégât possible, temps
## du jeu arrêté. Seul ce menu continue de répondre, grâce à son mode de
## traitement qui ignore la pause.
##
## Échap n'ouvre le menu que si aucune autre interface n'est ouverte : un
## inventaire affiché se ferme en priorité, ce qui correspond à ce qu'attend
## le joueur.

@onready var _resume_button: Button = $Layout/Panel/Margin/Content/ResumeButton
@onready var _save_button: Button = $Layout/Panel/Margin/Content/SaveButton
@onready var _quit_button: Button = $Layout/Panel/Margin/Content/QuitButton
@onready var _notice: Label = $Layout/Panel/Margin/Content/Notice


func _ready() -> void:
	hide()
	_notice.text = ""

	_resume_button.pressed.connect(close)
	_save_button.pressed.connect(_on_save_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	if visible:
		close()
		get_viewport().set_input_as_handled()
		return

	# Une interface ouverte a la priorité : elle se ferme sur Échap, pas nous.
	if UiState.is_any_open():
		return

	open()
	get_viewport().set_input_as_handled()


func open() -> void:
	if visible:
		return

	_notice.text = ""
	show()
	UiState.push_ui()
	GameManager.set_paused(true)
	_resume_button.grab_focus()


func close() -> void:
	if not visible:
		return

	hide()
	GameManager.set_paused(false)
	UiState.pop_ui()


func _on_save_pressed() -> void:
	_notice.text = "Partie sauvegardée" if SaveManager.save_game() else "Échec de la sauvegarde"


## Quitter depuis la pause sauvegarde avant de revenir à l'écran titre.
func _on_quit_pressed() -> void:
	SaveManager.save_game()
	hide()
	UiState.pop_ui()
	GameManager.return_to_menu()
