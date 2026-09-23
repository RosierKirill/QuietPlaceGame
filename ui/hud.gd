class_name Hud
extends CanvasLayer

## Interface de jeu : viseur, invite d'interaction, barres de vie et d'énergie.
##
## Le HUD ne fait qu'observer : il se connecte aux signaux des composants du
## joueur et ne modifie jamais leur état.

## Émis quand le joueur demande à réapparaître depuis l'écran de mort.
signal respawn_requested

## Chemin vers le [InteractionRay] du joueur, défini dans la scène.
@export var interaction_ray_path: NodePath
## Chemin vers le composant [Health] du joueur.
@export var health_path: NodePath
## Chemin vers le composant [Energy] du joueur.
@export var energy_path: NodePath
## Chemin vers le [Need] de faim.
@export var hunger_path: NodePath
## Chemin vers le [Need] de soif.
@export var thirst_path: NodePath
## Chemin vers le [Need] de souffle. La barre ne s'affiche que sous l'eau.
@export var breath_path: NodePath

@onready var _interaction_prompt: Label = $InteractionPrompt
@onready var _inventory_panel: InventoryPanel = $InventoryPanel
@onready var _crafting_panel: CraftingPanel = $CraftingPanel
@onready var _container_panel: ContainerPanel = $ContainerPanel
@onready var _death_screen: DeathScreen = $DeathScreen
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _clock_label: Label = $Clock
@onready var _notice: Label = $Notice
@onready var _health_bar: ProgressBar = $Bars/HealthBar
@onready var _energy_bar: ProgressBar = $Bars/EnergyBar
@onready var _hunger_bar: ProgressBar = $Bars/HungerBar
@onready var _thirst_bar: ProgressBar = $Bars/ThirstBar
@onready var _breath_bar: ProgressBar = $Bars/BreathBar


func _ready() -> void:
	_interaction_prompt.hide()
	_death_screen.respawn_requested.connect(respawn_requested.emit)
	_notice.hide()
	_bind_interaction_ray()
	_update_clock()

	SaveManager.game_saved.connect(_on_game_saved)
	SaveManager.game_loaded.connect(_on_game_loaded)
	SaveManager.save_failed.connect(_on_save_failed)
	_bind_health()
	_bind_energy()
	_bind_need(hunger_path, _hunger_bar)
	_bind_need(thirst_path, _thirst_bar)
	_bind_need(breath_path, _breath_bar)
	# Le souffle ne s'affiche que quand il manque : hors de l'eau, il est plein
	# et la barre n'apprend rien.
	var breath := get_node_or_null(breath_path) as Need
	if breath != null:
		breath.need_changed.connect(func(current: float, maximum: float) -> void:
			_breath_bar.visible = current < maximum - 0.01)
		_breath_bar.visible = false


func _bind_interaction_ray() -> void:
	var ray := get_node_or_null(interaction_ray_path) as InteractionRay
	if ray == null:
		push_warning("Hud : aucun InteractionRay trouvé à '%s'." % interaction_ray_path)
		return

	ray.focus_changed.connect(_on_focus_changed)


func _bind_health() -> void:
	var health := get_node_or_null(health_path) as Health
	if health == null:
		push_warning("Hud : aucun Health trouvé à '%s'." % health_path)
		return

	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _bind_energy() -> void:
	var energy := get_node_or_null(energy_path) as Energy
	if energy == null:
		push_warning("Hud : aucun Energy trouvé à '%s'." % energy_path)
		return

	energy.energy_changed.connect(_on_energy_changed)
	_on_energy_changed(energy.current_energy, energy.max_energy)


func _process(_delta: float) -> void:
	_update_clock()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		SaveManager.save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		SaveManager.load_game()
		get_viewport().set_input_as_handled()


func _on_game_saved() -> void:
	_show_notice("Partie sauvegardée")


func _on_game_loaded() -> void:
	_show_notice("Partie chargée")


func _on_save_failed(reason: String) -> void:
	_show_notice(reason)


## Affiche un message passager, puis l'efface.
func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.show()

	var timer := get_tree().create_timer(2.5)
	await timer.timeout

	# Un autre message a pu s'afficher entre-temps : on ne l'écrase pas.
	if _notice.text == text:
		_notice.hide()


## Affiche l'heure et le jour courants.
func _update_clock() -> void:
	_clock_label.text = "Jour %d  ·  %s" % [TimeOfDay.day, TimeOfDay.get_clock_text()]


## Affiche l'écran de mort.
##
## Ferme d'abord toute interface ouverte : mourir l'inventaire ouvert laissait
## la grille à l'écran par-dessus l'écran de mort, et faussait le décompte des
## interfaces qui gère le curseur.
func show_death(message: String = "") -> void:
	close_all_panels()
	_death_screen.show_death(message)


## Ferme les interfaces modales encore ouvertes.
func close_all_panels() -> void:
	_inventory_panel.close()
	_crafting_panel.close()
	_container_panel.close()
	_pause_menu.close()


## Ouvre l'interface de fabrication pour [param recipes].
func open_crafting(recipes: Array, inventory: Inventory) -> void:
	_crafting_panel.open_with(recipes, inventory)


## Ouvre l'interface d'un conteneur face à l'inventaire du joueur.
func open_container(container: Inventory, player_inventory: Inventory) -> void:
	_container_panel.open_with(container, player_inventory)


## Relie un besoin à sa barre. La barre rougit au niveau critique, ce qui
## avertit sans avoir à lire un chiffre.
func _bind_need(path: NodePath, bar: ProgressBar) -> void:
	var need := get_node_or_null(path) as Need
	if need == null:
		bar.hide()
		return

	var update := func(current: float, maximum: float) -> void:
		bar.max_value = maximum
		bar.value = current
		bar.modulate = Color(1.4, 0.5, 0.5) if need.is_critical() else Color.WHITE

	need.need_changed.connect(update)
	update.call(need.current_value, need.max_value)


## Affiche ou masque l'invite selon l'objet visé.
func _on_focus_changed(interactable: Interactable) -> void:
	if interactable == null:
		_interaction_prompt.hide()
		return

	_interaction_prompt.text = "[E] %s" % interactable.prompt
	_interaction_prompt.show()


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_energy_changed(current: float, maximum: float) -> void:
	_energy_bar.max_value = maximum
	_energy_bar.value = current
