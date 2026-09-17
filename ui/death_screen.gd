class_name DeathScreen
extends Control

## Écran affiché à la mort du joueur.
##
## Rend la souris, propose de réapparaître, et signale le choix plutôt que
## d'agir lui-même : c'est au joueur de décider ce que « réapparaître » veut
## dire, pas à l'interface.

## Émis quand le joueur demande à réapparaître.
signal respawn_requested

@onready var _respawn_button: Button = $Background/Margin/Content/RespawnButton
@onready var _message: Label = $Background/Margin/Content/Message


func _ready() -> void:
	hide()
	_respawn_button.pressed.connect(_on_respawn_pressed)


## Affiche l'écran. [param message] permet d'indiquer la cause de la mort.
func show_death(message: String = "") -> void:
	if visible:
		return

	_message.text = message if message != "" else "Vous êtes mort."
	show()
	UiState.push_ui()
	_respawn_button.grab_focus()


func hide_death() -> void:
	if not visible:
		return

	hide()
	UiState.pop_ui()


func _on_respawn_pressed() -> void:
	hide_death()
	respawn_requested.emit()
