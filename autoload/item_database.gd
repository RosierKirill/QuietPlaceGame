extends Node

## Retrouve un [Item] à partir de son identifiant.
##
## Autoload. Une sauvegarde ne peut pas contenir de références à des ressources ;
## elle ne stocke que des identifiants. C'est ici qu'on refait le lien au
## chargement.

## Dossier scanné au démarrage.
const ITEMS_DIRECTORY: String = "res://items/"

var _items_by_id: Dictionary = {}


func _ready() -> void:
	_scan_directory(ITEMS_DIRECTORY)


## Retourne l'objet portant [param id], ou null s'il n'existe pas.
func get_item(id: StringName) -> Item:
	return _items_by_id.get(id, null)


func has_item(id: StringName) -> bool:
	return _items_by_id.has(id)


## Charge chaque ressource .tres du dossier et indexe celles qui sont des Item.
func _scan_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_warning("ItemDatabase : dossier introuvable '%s'." % path)
		return

	for file_name in directory.get_files():
		# Les exports transforment les .tres en .remap : on rétablit le nom.
		var clean_name := file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres"):
			continue

		var resource := load(path + clean_name)
		if resource is Item:
			var item := resource as Item
			if item.id != &"":
				_items_by_id[item.id] = item

	# Les recettes vivent dans un sous-dossier ; on ne descend pas dedans.
