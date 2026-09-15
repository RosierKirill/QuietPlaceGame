# Architecture

Ce document décrit l'organisation technique du projet et les patterns adoptés.
Il s'appuie sur la proposition d'architecture validée (moteur Godot 4, GDScript).

## Principes directeurs

1. **Composition par scènes/nœuds.** Chaque entité (joueur, mob, ressource, coffre)
   est une scène instanciable. On privilégie de petits nœuds réutilisables
   (ex. un nœud `Health`, une `Hitbox`) plutôt que de gros scripts monolithiques.
2. **Données découplées de la logique — Custom Resources.** Les items et les recettes
   de craft sont des `Resource` (`.tres`) : des données pures, éditables dans
   l'inspecteur. Ajouter un minerai ou une recette = ajouter une donnée, pas du code.
3. **Hitbox / Hurtbox (Area3D).** Un seul système de dégâts pour tout : combat à la
   dague, coups des mobs, et récolte (frapper un arbre). Une `Hitbox` inflige, une
   `Hurtbox` reçoit, un composant `Health` encaisse.
4. **Machine à états (State Machine).** Pour l'IA des mobs (idle / wander / chase /
   attack / flee). Le mouton et le zombie partagent l'architecture ; seuls les
   états actifs diffèrent.

## Rôle des dossiers

| Dossier | Contenu attendu |
|---|---|
| `autoload/` | Singletons (Autoload) : `GameManager`, `ItemDatabase`, `SaveManager`. À utiliser avec parcimonie. |
| `player/` | `player.tscn` + scripts : contrôleur `CharacterBody3D`, caméra, interaction. |
| `systems/inventory/` | Modèle d'inventaire, slots, drag & drop, hotbar. |
| `systems/crafting/` | Table de craft, résolution de recettes. |
| `systems/combat/` | `Hitbox`, `Hurtbox`, composant `Health`, `Energy`. |
| `systems/interaction/` | Raycast d'interaction, prompt « [E] ». |
| `entities/mobs/` | `sheep.tscn` (passif), `zombie.tscn` (hostile) + state machine. |
| `entities/resources/` | Scène générique `Harvestable` + arbre, pierre, minerais. |
| `items/` | Ressources `.tres` : chaque item, chaque recette. |
| `ui/` | HUD (barres HP/énergie), écrans inventaire et craft. |
| `world/` | Niveaux (`test_room.tscn`, scène de démo). |
| `assets/` | Modèles 3D, textures, sons. |

## Flux de dépendances (haut niveau)

```
Contrôleur FPS ──► Interaction (raycast)
      │                   │
      ▼                   ▼
  HP / Énergie        Inventaire ──► Hotbar
                          │              │
                          ▼              ▼
                    Récolte          Combat (dague, Hitbox)
                          │              │
                          ▼              ▼
                   Craft / Coffre     Mobs (zombie, mouton)
```

Voir `ROADMAP.md` pour le découpage en epics/tâches et l'ordre d'implémentation.
