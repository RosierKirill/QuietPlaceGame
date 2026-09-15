# Conventions de code

Objectif : un projet lisible et standardisé, aligné sur les pratiques de la
communauté Godot.

## GDScript

On suit le [guide de style GDScript officiel](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) :

- **Indentation par tabulations** (pas d'espaces) — imposé aussi par `.editorconfig`.
- Ordre dans un script : `class_name` → `extends` → `## docstring` → signaux →
  enums → constantes → variables exportées (`@export`) → variables → `@onready` →
  méthodes (`_ready`, `_process`, puis le reste).
- `snake_case` pour les variables, fonctions et **noms de fichiers**.
- `PascalCase` pour les `class_name`, les noms de nœuds et de scènes.
- `CONSTANT_EN_MAJUSCULES` pour les constantes.
- Préfixe `_` pour les membres privés (ex. `_update_ui`).
- Typage statique autant que possible : `var pv: int = 100`, `func heal(x: int) -> void:`.

## Nommage des fichiers

- Scripts : `player_controller.gd`, `inventory.gd`.
- Scènes : `player.tscn`, `zombie.tscn`.
- Ressources d'items : `wood.tres`, `iron_ore.tres` dans `items/`.

## Git & commits

- Un commit par tâche de la roadmap quand c'est possible.
- Format [Conventional Commits](https://www.conventionalcommits.org/) :
  - `feat: ajoute le contrôleur FPS de base` (GAME-102)
  - `fix: corrige la consommation d'énergie au sprint`
  - `docs: complète le README`
  - `chore: met en place la structure du projet`
  - `refactor: extrait le composant Health`
- Référencer l'ID de tâche dans le corps du commit quand pertinent (ex. `GAME-102`).

## Branches (optionnel pour un dev solo)

- `main` : toujours dans un état qui se lance.
- Branches de feature `feat/GAME-102-fps-controller` si tu veux isoler un chantier.
