extends Node

## Suit l'ouverture des interfaces modales (inventaire, craft, coffre).
##
## Autoload. Centralise le mode de la souris : dès qu'au moins une interface
## est ouverte, le curseur est rendu au joueur et la vue cesse de tourner.
## Évite que chaque écran gère la souris dans son coin et se contredise.

## Émis quand on passe de « aucune interface » à « au moins une », et inversement.
signal ui_open_changed(is_open: bool)

## Nombre d'interfaces modales actuellement ouvertes.
var _open_count: int = 0


## Signale l'ouverture d'une interface modale.
func push_ui() -> void:
	_open_count += 1
	if _open_count == 1:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		ui_open_changed.emit(true)


## Signale la fermeture d'une interface modale.
func pop_ui() -> void:
	_open_count = maxi(_open_count - 1, 0)
	if _open_count == 0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		ui_open_changed.emit(false)


func is_any_open() -> bool:
	return _open_count > 0
