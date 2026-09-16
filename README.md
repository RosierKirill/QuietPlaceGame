# Quiet Place Game

Jeu de survie / RPG à la **première personne** — POC `v0.1.0`.
Moteur : **[Godot 4](https://godotengine.org/)** · Langage : **GDScript**.
Inspirations : Half-Life, Skyrim, 7 Days to Die, Minecraft.

## État du projet

Prototype jouable de bout en bout. Toutes les mécaniques du POC sont en place :
on se déplace, on récolte, on fabrique, on stocke, on se bat.

## Fonctionnalités

- **Déplacement première personne** — marche, saut, sprint consommant de l'énergie
- **Vie et énergie** — deux barres, régénération différée de l'énergie
- **Interaction** — rayon depuis la caméra, invite « [E] » contextuelle
- **Inventaire** — 24 emplacements, empilement, glisser-déposer, scission de pile
- **Barre rapide** — 6 emplacements, sélection au clavier ou à la molette
- **Objets au sol** — ramassage, avec report du surplus si l'inventaire est plein
- **Récolte** — arbre, rocher, veine de fer, veine de charbon, chacun avec son butin
- **Combat** — dague équipable, zone de dégâts ouverte le temps du geste
- **Créatures** — mouton passif qui fuit, zombie hostile qui poursuit et frappe
- **Fabrication** — table de craft, recettes en ressources de données
- **Stockage** — coffre, avec transfert par glisser-déposer entre inventaires

## Prérequis

**Godot 4.3** ou supérieur ([télécharger](https://godotengine.org/download)) — édition
standard (GDScript), la version .NET n'est pas nécessaire.

## Lancer le projet

1. Ouvrir **Godot 4**, choisir `Importer` et sélectionner le fichier `project.godot`.
2. Ouvrir le projet, puis `F5`.

La scène lancée est `world/demo.tscn`. La scène `world/test_room.tscn` est conservée
comme bac à sable minimal pour tester un système isolément.

## Contrôles

| Action | Touche |
|---|---|
| Se déplacer | Z / Q / S / D |
| Sauter | Espace |
| Sprinter | Maj |
| Interagir / ramasser | E |
| Attaquer | Clic gauche |
| Inventaire | Tab |
| Barre rapide | 1 à 6 (rangée du haut) ou molette |
| Scinder une pile | Clic droit sur l'emplacement |
| Fermer une interface | Échap |

> Les touches sont liées par **position physique** : sur un clavier AZERTY, les
> emplacements 1 à 6 correspondent donc à la rangée `& é " ' ( -`, sans Maj.

## Boucle de jeu

Ramasser la dague au sol → la sélectionner dans la barre rapide → abattre un arbre →
ramasser le bois → ouvrir la table de fabrication → produire des planches. Le minerai
de fer et le charbon donnent un lingot. Le coffre sert à déposer le surplus. Le zombie
attaque à vue ; le mouton s'enfuit.

## Structure du projet

| Dossier | Rôle |
|---|---|
| `autoload/` | Singletons globaux (`UiState` : ouverture des interfaces et mode souris) |
| `player/` | Contrôleur première personne, caméra, porte-arme |
| `systems/ai/` | Machine à états générique |
| `systems/combat/` | `Health`, `Energy`, `Hitbox`, `Hurtbox` |
| `systems/crafting/` | `Recipe` et ses ingrédients |
| `systems/interaction/` | Rayon d'interaction, composant `Interactable` |
| `systems/inventory/` | `Item`, `ItemStack`, `Inventory` |
| `entities/items/` | Objets posés au sol |
| `entities/mobs/` | `Mob` et ses états, mouton, zombie |
| `entities/resources/` | Ressources récoltables |
| `entities/stations/` | Table de fabrication, coffre |
| `items/` | Définitions d'objets et de recettes (`.tres`) |
| `ui/` | HUD, inventaire, barre rapide, craft, coffre |
| `world/` | Scène de démo et salle de test |
| `assets/` | Icônes |

Détail des choix techniques : [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Feuille de route : [`docs/ROADMAP.md`](docs/ROADMAP.md).
Conventions de code : [`docs/CODING_STYLE.md`](docs/CODING_STYLE.md).

## Principes d'architecture

Trois choix structurent tout le projet :

**Les données sont séparées du code.** Objets et recettes sont des `Resource`
(`.tres`). Ajouter un minerai ou une recette ne demande pas une ligne de code.

**Un seul système de dégâts.** Une `Hitbox` s'ouvre le temps d'un geste et touche une
`Hurtbox`, qui transmet à un `Health`. Frapper un arbre et frapper un zombie, c'est le
même chemin — seul diffère ce qui arrive à zéro point de vie.

**Le comportement se compose dans la scène.** Mouton et zombie partagent le script
`Mob` et la même machine à états ; seuls les états présents dans leur scène changent.

## Licence

[MIT](LICENSE) — © 2026 Kirill Rosier.
