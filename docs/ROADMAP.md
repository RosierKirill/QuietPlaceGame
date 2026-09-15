# Roadmap POC — Jeu de survie / RPG première personne (Godot 4)

*Version 1 du POC : toutes les mécaniques citées, fonctionnelles ensemble. Moteur : Godot 4, GDScript.*

---

## Notre méthode de travail (contrat)

Tu as posé deux conditions. Elles cadrent toute la suite :

1. **Projet exemplaire et standardisé.** On suit les conventions officielles Godot et les standards des projets open-source sérieux : structure de dossiers claire, conventions de nommage, Git dès le début avec commits conventionnels, README, LICENSE, `.gitignore` Godot, style GDScript officiel, découplage données/logique (Custom Resources), et un pattern réutilisé partout (Hitbox/Hurtbox + composant Health).

2. **Human first, initiative minimale de ma part.** Concrètement, la règle qu'on applique :
   - Je ne code **aucune tâche** sans que tu l'aies validée d'abord.
   - Je n'ajoute **aucune feature** hors de la roadmap sans te demander.
   - On avance **une tâche à la fois**, dans l'ordre. Pour chaque tâche : je t'explique *quoi* et *pourquoi* → tu valides → je produis un incrément **petit et lisible** → tu testes → on coche.
   - À chaque étape je t'explique le *pourquoi* d'un choix technique pour que tu gardes la main, pas seulement le *quoi*.
   - Si une décision se présente (2 façons de faire), je te la remonte au lieu de trancher seul.

> Cette roadmap est le **backlog**. Rien n'est codé tant que tu ne dis pas « go » sur une tâche.

---

## Structure du backlog

Le POC est découpé en **8 epics** (= 8 sprints, chacun livrant quelque chose de testable). Chaque epic contient des **tâches** avec un identifiant `GAME-xxx`, une **définition de « terminé »** (Definition of Done) et ses **dépendances**.

**Conventions de statut (colonnes Kanban) :**

| **#** | **Statut** | **Signification** |
|---|---|---|
| **1** | **Backlog** | Prévu, pas encore prêt à démarrer (dépendances non finies) |
| **2** | **To Do** | Prêt à démarrer, en attente de ton « go » |
| **3** | **In Progress** | En cours de développement |
| **4** | **In Review** | Codé, en attente de ton test/validation |
| **5** | **Done** | Testé et validé par toi |

**Convention de priorité :** P0 = bloquant/fondation · P1 = cœur du POC · P2 = confort, peut glisser.

---

## Epic 0 — Fondations & standards du projet `[P0]`

*Objectif : un dépôt propre, standardisé, prêt à recevoir du code. C'est ce qui rend le projet « exemplaire ».*

**Tableau des tâches — Epic 0**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-001 | Créer le projet Godot 4 + init dépôt Git | Projet ouvre dans Godot 4.x ; `git init` fait ; premier commit | — |
| **2** | GAME-002 | Ajouter `.gitignore` Godot officiel | `.godot/`, exports et fichiers temp ignorés | GAME-001 |
| **3** | GAME-003 | Mettre en place l'arborescence de dossiers | Dossiers `player/ systems/ entities/ items/ ui/ world/ autoload/ assets/` créés | GAME-001 |
| **4** | GAME-004 | Choisir et ajouter une LICENSE | Fichier `LICENSE` présent (MIT recommandé) | GAME-001 |
| **5** | GAME-005 | Rédiger le README initial | README : titre, but, moteur/version, comment lancer, structure | GAME-003 |
| **6** | GAME-006 | Adopter le guide de style GDScript officiel + convention de nommage | Note dans le README : snake_case fichiers, PascalCase classes/nœuds, commits conventionnels | GAME-005 |
| **7** | GAME-007 | Configurer la map d'entrées (Input Map) de base | Actions `move_*`, `jump`, `sprint`, `interact`, `attack`, `inventory` définies dans les réglages projet | GAME-001 |

---

## Epic 1 — Contrôleur FPS & monde de test `[P0]`

*Objectif : on se déplace à la première personne dans une salle et on peut « viser » des objets.*

**Tableau des tâches — Epic 1**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-101 | Salle de test (sol, murs, lumière) | Une scène `world/test_room.tscn` avec sol + éclairage, jouable | GAME-003 |
| **2** | GAME-102 | Contrôleur FPS (`CharacterBody3D` + `Camera3D`) | Déplacement ZQSD, regard souris, gravité, capture/libération curseur | GAME-101, GAME-007 |
| **3** | GAME-103 | Saut + sprint | Saut au sol, sprint qui augmente la vitesse | GAME-102 |
| **4** | GAME-104 | Système d'interaction par raycast | `RayCast3D` caméra détecte les objets « interactifs » ; prompt « [E] » à l'écran | GAME-102 |

---

## Epic 2 — Survie de base : HP & énergie `[P1]`

*Objectif : barres de vie et d'énergie fonctionnelles, base des dégâts.*

**Tableau des tâches — Epic 2**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-201 | Composant `Health` réutilisable (nœud) | Max/valeur courante, méthodes `take_damage`/`heal`, signaux `health_changed`/`died` | GAME-003 |
| **2** | GAME-202 | Composant `Energy`/Stamina | Consommation (sprint), régénération, signaux | GAME-201, GAME-103 |
| **3** | GAME-203 | HUD : barre HP + barre énergie | 2 `ProgressBar` reliées aux composants par signaux, mise à jour en temps réel | GAME-201, GAME-202 |
| **4** | GAME-204 | Brancher HP/énergie sur le joueur | Le sprint vide l'énergie ; « mourir » (test) déclenche `died` | GAME-202, GAME-203 |

---

## Epic 3 — Objets & inventaire `[P1]`

*Objectif : ramasser des objets, les voir dans un inventaire, une hotbar, drag & drop.*

**Tableau des tâches — Epic 3**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-301 | `Item` en Custom Resource | Ressource `.tres` : id, nom, icône, stackable, taille de stack max | GAME-003 |
| **2** | GAME-302 | Créer les premiers items (`.tres`) | Bois, pierre, fer, charbon, dague définis comme ressources | GAME-301 |
| **3** | GAME-303 | Modèle de données Inventaire | Tableau de slots, ajout/retrait, stacking, signaux de changement | GAME-301 |
| **4** | GAME-304 | UI Inventaire (grille de slots) | Ouvre/ferme (touche inventaire), affiche items + quantités | GAME-303 |
| **5** | GAME-305 | Ramassage d'objets au sol | Objet interactif → « [E] » → entre dans l'inventaire, disparaît du sol | GAME-304, GAME-104 |
| **6** | GAME-306 | Drag & drop entre slots | Déplacer/fusionner/scinder des stacks à la souris | GAME-304 |
| **7** | GAME-307 | Hotbar (barre rapide) | 1er rang d'items sélectionnable au clavier/molette ; slot actif visible | GAME-304 |

---

## Epic 4 — Récolte de ressources `[P1]`

*Objectif : frapper un arbre / un rocher / un minerai et récupérer les ressources.*

**Tableau des tâches — Epic 4**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-401 | Scène générique `Harvestable` (Hurtbox + Health) | Un nœud récoltable configurable : PV, item(s) lâchés, quantité | GAME-201, GAME-301 |
| **2** | GAME-402 | Arbre récoltable → bois | Frapper l'arbre le détruit à 0 PV et lâche du bois | GAME-401 |
| **3** | GAME-403 | Pierre récoltable → pierre | Idem, lâche de la pierre | GAME-401 |
| **4** | GAME-404 | Minerai de fer → fer | Idem, lâche du minerai de fer | GAME-401 |
| **5** | GAME-405 | Minerai de charbon → charbon | Idem, lâche du charbon | GAME-401 |
| **6** | GAME-406 | Objet ramassé → inventaire | Les drops de récolte rentrent bien dans l'inventaire/stacking | GAME-402, GAME-305 |

---

## Epic 5 — Combat & mobs `[P1]`

*Objectif : dague qui frappe, un zombie qui poursuit et attaque, un mouton passif qui fuit.*

**Tableau des tâches — Epic 5**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-501 | Pattern Hitbox/Hurtbox (Area3D) documenté | Hitbox inflige aux Hurtbox ; générique (arme, mob, récolte) | GAME-201 |
| **2** | GAME-502 | Équiper la dague depuis la hotbar | Sélectionner la dague l'affiche en main | GAME-307, GAME-302 |
| **3** | GAME-503 | Attaque à la dague (Hitbox + animation) | Clic gauche → hitbox active un court instant → inflige des dégâts | GAME-501, GAME-502 |
| **4** | GAME-504 | Machine à états d'IA générique | États idle / wander / chase / attack / flee réutilisables | GAME-003 |
| **5** | GAME-505 | Navigation (`NavigationAgent3D`) sur la salle de test | Les mobs se déplacent en évitant les obstacles | GAME-504, GAME-101 |
| **6** | GAME-506 | Mob **zombie** (hostile) | idle → chase (repère le joueur) → attack (Hitbox) ; a un `Health`, meurt sous la dague | GAME-503, GAME-505 |
| **7** | GAME-507 | Mob **mouton** (passif) | wander → flee (fuit quand le joueur approche/frappe) ; a un `Health`, meurt sous la dague | GAME-504, GAME-505 |
| **8** | GAME-508 | Le zombie inflige des dégâts au joueur | L'attaque du zombie baisse les HP du joueur (via Hurtbox joueur) | GAME-506, GAME-204 |

---

## Epic 6 — Craft & stockage `[P1]`

*Objectif : une table de craft avec recettes, et un coffre pour stocker.*

**Tableau des tâches — Epic 6**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-601 | `Recipe` en Custom Resource | Ressource `.tres` : ingrédients (item+quantité) → résultat (item+quantité) | GAME-301 |
| **2** | GAME-602 | Définir 2-3 recettes de départ | Ex. : X bois → planches ; fer + charbon → lingot (placeholder) | GAME-601, GAME-302 |
| **3** | GAME-603 | Scène `Crafting Table` interactive | « [E] » sur la table → ouvre l'UI de craft | GAME-104, GAME-601 |
| **4** | GAME-604 | UI de craft + résolution de recette | Affiche recettes réalisables ; craft consomme les ingrédients et produit le résultat | GAME-603, GAME-303 |
| **5** | GAME-605 | Scène `Chest`/boîte (second inventaire) | « [E] » sur la boîte → ouvre son inventaire | GAME-104, GAME-303 |
| **6** | GAME-606 | Transfert joueur ⇄ coffre | Drag & drop des items entre inventaire joueur et coffre | GAME-605, GAME-306 |

---

## Epic 7 — Intégration & livraison du POC `[P1]`

*Objectif : tout marche ensemble, c'est propre, c'est buildé.*

**Tableau des tâches — Epic 7**

| **#** | **ID** | **Tâche** | **Definition of Done** | **Dépend de** |
|---|---|---|---|---|
| **1** | GAME-701 | Scène de démo « vertical slice » | Une map assemblant : joueur, arbres/pierres/minerais, mouton, zombie, table de craft, coffre | Tous les epics 1-6 |
| **2** | GAME-702 | Passe de bugs & cohérence | Parcours complet sans blocage : récolter → crafter → combattre → stocker | GAME-701 |
| **3** | GAME-703 | README final + captures | README à jour (features, contrôles, screenshots) | GAME-702 |
| **4** | GAME-704 | Export desktop + tag `v0.1.0` | Build Windows/Linux fonctionnel ; commit taggé `v0.1.0` | GAME-702 |

---

## Vue d'ensemble : ordre et jalons

**Tableau récapitulatif des epics**

| **#** | **Epic (sprint)** | **Livrable testable** | **Priorité** | **Nb tâches** |
|---|---|---|---|---|
| **1** | Epic 0 — Fondations & standards | Dépôt propre, prêt à coder | P0 | 7 |
| **2** | Epic 1 — Contrôleur FPS & monde | On se déplace et on vise | P0 | 4 |
| **3** | Epic 2 — HP & énergie | Barres fonctionnelles, dégâts de base | P1 | 4 |
| **4** | Epic 3 — Objets & inventaire | Ramasser, ranger, hotbar | P1 | 7 |
| **5** | Epic 4 — Récolte | Couper arbre / miner pierre, fer, charbon | P1 | 6 |
| **6** | Epic 5 — Combat & mobs | Dague, zombie hostile, mouton passif | P1 | 8 |
| **7** | Epic 6 — Craft & stockage | Table de craft + coffre | P1 | 6 |
| **8** | Epic 7 — Intégration & livraison | **POC v0.1.0 jouable de bout en bout** | P1 | 4 |

**Total : 8 epics, 46 tâches.** Chemin critique : Epic 0 → 1 → 2/3 → 4 → 5 → 6 → 7. Les epics 2 et 3 peuvent partiellement se chevaucher, mais on reste sur du séquentiel « une tâche à la fois » comme convenu.

---

## Prochaine décision pour toi

1. Cette découpe te convient-elle (granularité, ordre, périmètre du POC) ? Tu peux me dire d'ajouter/retirer/fusionner des tâches — c'est ton backlog.
2. **Où créer le board Notion ?** (voir la question que je te pose dans le chat)
