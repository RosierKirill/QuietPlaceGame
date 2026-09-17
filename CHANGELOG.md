# Changelog

Toutes les évolutions notables du projet sont consignées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
versionnage [SemVer](https://semver.org/lang/fr/).

## [0.2.0] - 2026-09-17

Boucle de survie, persistance et menus.

### Ajouté
- Composant `Need` générique : faim et soif, avec seuil critique et dégâts à zéro.
- Objets consommables définis en données seules ; baies, eau et viande.
- `LootTable` partagée : les créatures lâchent du butin comme les ressources.
- Repousse des ressources ; buisson à baies cueillable indéfiniment.
- Cycle jour/nuit complet : horloge, éclairage dynamique, heure à l'écran.
- Zombies plus dangereux la nuit et apparition nocturne plafonnée.
- Écran de mort, réapparition et sac de butin laissé au point de mort.
- Sauvegarde générique par contrat, manuelle, automatique et à la fermeture.
- Écran titre et menu pause figeant réellement la partie.

### Corrigé
- L'invite d'interaction restait affichée après la destruction de sa cible.
- Le chargement laissait un monde amputé de ce qui avait été détruit.
- Plantage à l'affichage d'un conteneur détruit pendant sa consultation.
- Sauvegarder depuis l'écran titre écrasait la partie par une partie vide.

## [0.1.0] - 2026-09-16

Premier prototype jouable de bout en bout.

### Ajouté
- Contrôleur première personne : marche, saut, sprint, rotation de la vue.
- Composants `Health` et `Energy` avec leurs barres à l'écran.
- Système d'interaction par rayon et invite contextuelle.
- Inventaire à emplacements : empilement, glisser-déposer, scission, barre rapide.
- Objets au sol ramassables.
- Ressources récoltables : arbre, rocher, veine de fer, veine de charbon.
- Système de dégâts `Hitbox` / `Hurtbox` partagé par la récolte et le combat.
- Dague équipable depuis la barre rapide.
- Machine à états générique et créatures : mouton passif, zombie hostile.
- Fabrication par recettes et table de craft.
- Coffre et transfert d'objets entre inventaires.
- Socle du projet : structure, conventions, documentation.

[0.2.0]: https://github.com/RosierKirill/QuietPlaceGame/releases/tag/v0.2.0
[0.1.0]: https://github.com/RosierKirill/QuietPlaceGame/releases/tag/v0.1.0
