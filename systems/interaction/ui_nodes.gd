class_name UiNodes
extends RefCounted

## Petites recherches partagées par les objets interactifs.
##
## Évite que chaque station réécrive la même boucle pour retrouver l'inventaire
## ou l'interface du joueur à partir du nœud qui a déclenché l'interaction.


## Retourne le composant [Inventory] enfant de [param node], ou null.
static func find_inventory(node: Node) -> Inventory:
	if node == null:
		return null

	for child in node.get_children():
		if child is Inventory:
			return child as Inventory

	return null


## Retourne le [Hud] enfant de [param node], ou null.
static func find_hud(node: Node) -> Hud:
	if node == null:
		return null

	for child in node.get_children():
		if child is Hud:
			return child as Hud

	return null
