# Rebond – contexte projet

## Le produit

Rebond est une app iPhone de rééducation à domicile.

1. Le patient prend en photo la feuille d'exercices donnée par son kiné (dessins, texte imprimé ou manuscrit).
2. L'IA embarquée la transforme en programme structuré : exercices, séries, répétitions, fréquence.
3. Pendant chaque séance, la caméra suit le corps du patient, compte les répétitions et corrige les mouvements en temps réel.
4. En fin de séance, le patient indique son niveau de douleur (0 à 10).
5. Chaque semaine, un rapport (exercices faits, répétitions, amplitude, douleur) est envoyé au kiné pour qu'il ajuste le programme.

Problème résolu : le kiné ne sait pas si un traitement échoue parce qu'il est inefficace ou parce que le patient a sauté ou mal fait ses exercices.

Interface en **français**.

## Contexte

Projet développé pendant le Build Challenge (Unaite, MWM, Apple, ⌘+F), les 15 et 16 octobre 2026. Équipe de deux développeurs. Objectif : une app fonctionnelle et un build soumis sur App Store Connect à la fin du deuxième jour. Le temps est très limité : privilégier ce qui marche et se démontre.

## Environnement

- Xcode 27.1, Swift 6.4, SDK iOS 27.1
- Cible de déploiement : iOS 27.0
- SwiftUI uniquement
- Frameworks Apple natifs uniquement, aucune dépendance tierce sans validation

## Frameworks utilisés

| Besoin | Framework |
|---|---|
| Lecture de la feuille d'exercices | Foundation Models (modèle embarqué, entrée d'image) |
| Caméra | AVFoundation |
| Détection de posture, angles, répétitions | Vision (body pose 2D/3D) |
| Stockage local | SwiftData |
| Enregistrement des séances | HealthKit |
| Abonnement | StoreKit 2 |

## Règles techniques

- **Tout reste sur l'appareil.** Aucune image, vidéo ou donnée de santé n'est envoyée sur un serveur. Seul le rapport hebdo part au kiné, sur action explicite du patient.
- **Foundation Models :** toujours vérifier la disponibilité du modèle avant de l'appeler et gérer proprement le cas où l'appareil n'est pas compatible.
- **Siri AI n'est pas disponible dans l'Union européenne** avec iOS 27 : ne construire aucune fonctionnalité dessus.
- **Interface adaptative (iPhone Duo, iPhone pliable sorti le 23 octobre 2026) :** aucune dimension fixe. Utiliser les size classes, la géométrie de scène et les conteneurs standards (`NavigationStack`, `NavigationSplitView`). L'app doit fonctionner ouverte, fermée, tournée et pliée.
- **Liquid Glass :** utiliser en priorité les styles et composants système (`.buttonStyle(.glass)`, barres d'outils). Le verre est réservé aux contrôles qui flottent au-dessus du contenu, par exemple les contrôles par-dessus le flux caméra pendant la séance. Respecter le réglage d'accessibilité « Réduire la transparence ».
- **Séparer la logique de l'interface :** l'analyse des mouvements et la lecture de la feuille ne dépendent pas de SwiftUI.

## Modèle économique

Freemium avec essai gratuit de 7 jours, puis abonnement Rebond+ : annuel (39,99 €), mensuel (9,99 €) ou pass rééducation 3 mois sans renouvellement (24,99 €). Prix provisoires.

## Façon de travailler

- Ne créer que ce qui est demandé : pas de fichiers, dossiers, abstractions ou fonctionnalités en plus.
- Rester simple et lisible : le code doit pouvoir être compris et repris rapidement par l'autre développeur.
