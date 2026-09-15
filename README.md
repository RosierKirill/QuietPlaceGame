# Quiet Place Game

Jeu de survie / RPG à la **première personne** — POC (`v0.1.0`).
Moteur : **[Godot 4](https://godotengine.org/)** · Langage : **GDScript**.
Inspirations : Half-Life, Skyrim, 7 Days to Die, Minecraft.

> ⚠️ Projet en cours de développement. Ce dépôt contient pour l'instant le **socle standardisé** (Epic 0). Les mécaniques de jeu arrivent ensuite, epic par epic.

## Objectif du POC

Un prototype jouable de bout en bout réunissant toutes les mécaniques de base :

- Contrôleur première personne (déplacement, saut, sprint)
- Inventaire (slots, drag & drop, hotbar) + ramassage d'objets
- Barres de vie (HP) et d'énergie
- Combat mêlée à la dague
- Mobs : un **mouton** (passif) et un **zombie** (hostile)
- Récolte de ressources : arbre, pierre, minerai de fer, minerai de charbon
- Stockage (coffre) et **table de craft** (recettes)

Feuille de route détaillée : voir `docs/ROADMAP.md`.

## Prérequis

- **Godot 4.3** ou supérieur ([télécharger](https://godotengine.org/download)) — édition standard (GDScript), pas besoin de la version .NET.

## Lancer le projet

1. Ouvrir **Godot 4**.
2. `Importer` → sélectionner le fichier `project.godot` à la racine de ce dossier.
3. Ouvrir le projet, puis `F5` pour lancer (la scène principale sera définie à l'Epic 1).

## Structure du projet

| Dossier | Rôle |
|---|---|
| `autoload/` | Singletons globaux (gestionnaire de jeu, base d'items, sauvegarde) |
| `player/` | Scène et scripts du joueur (contrôleur FPS, caméra) |
| `systems/` | Systèmes de jeu : `inventory/`, `crafting/`, `combat/`, `interaction/` |
| `entities/` | `mobs/` (mouton, zombie) et `resources/` (arbre, pierre, minerais) |
| `items/` | Définitions d'items et de recettes (Custom Resources `.tres`) |
| `ui/` | Interfaces : HUD, inventaire, craft |
| `world/` | Niveaux et scènes de monde |
| `assets/` | Modèles, textures, sons |
| `docs/` | Documentation (architecture, style, roadmap) |

Détail : `docs/ARCHITECTURE.md`.

## Contrôles (par défaut)

| Action | Touche |
|---|---|
| Se déplacer | Z / Q / S / D |
| Sauter | Espace |
| Sprinter | Maj (Shift) |
| Interagir | E |
| Attaquer | Clic gauche |
| Inventaire | Tab |

## Contribution & conventions

Voir `docs/CODING_STYLE.md`. En résumé : guide de style GDScript officiel, fichiers en `snake_case`, classes/nœuds en `PascalCase`, commits au format [Conventional Commits](https://www.conventionalcommits.org/).

## Licence

[MIT](LICENSE) — © 2026 Kirill Rosier.
