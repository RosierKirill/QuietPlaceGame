extends Control

## Écran titre.
##
## « Continuer » n'apparaît que si une sauvegarde existe, et « Nouvelle partie »
## demande confirmation quand elle en écraserait une.

@onready var _continue_button: Button = $Layout/Panel/Margin/Content/ContinueButton
@onready var _new_game_button: Button = $Layout/Panel/Margin/Content/NewGameButton
@onready var _quit_button: Button = $Layout/Panel/Margin/Content/QuitButton
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmNewGame


func _ready() -> void:
	# L'écran titre s'affiche aussi si le jeu a été quitté en pause.
	GameManager.set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_continue_button.visible = SaveManager.has_save()
	_continue_button.pressed.connect(GameManager.continue_game)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_quit_button.pressed.connect(GameManager.quit_game)
	_confirm_dialog.confirmed.connect(GameManager.start_new_game)

	if _continue_button.visible:
		_continue_button.grab_focus()
	else:
		_new_game_button.grab_focus()


## Une partie neuve efface la sauvegarde : on ne le fait pas sans demander.
func _on_new_game_pressed() -> void:
	if SaveManager.has_save():
		_confirm_dialog.popup_centered()
		return

	GameManager.start_new_game()
