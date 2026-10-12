# Rebond – contexte projet

## Le produit

Rebond est une app iPhone de rééducation à domicile.

1. Le patient prend en photo la feuille d'exercices donnée par son kiné (dessins, texte imprimé ou manuscrit).
2. L'IA embarquée la transforme en programme structuré : exercices, séries, répétitions, fréquence. Le patient vérifie et corrige le programme avant de l'enregistrer.
3. Pendant chaque séance, la caméra suit le corps du patient, compte les répétitions et corrige les mouvements en temps réel.
4. En fin de séance, le patient indique son niveau de douleur (0 à 10).
5. Chaque semaine, un rapport (exercices faits, répétitions, amplitude, douleur) est envoyé au kiné pour qu'il ajuste le programme.

**Problème résolu :** le kiné ne sait pas si un traitement échoue parce qu'il est inefficace ou parce que le patient a sauté ou mal fait ses exercices.

**Ce que Rebond n'est pas :** un dispositif médical. L'app ne pose pas de diagnostic et ne modifie jamais le programme elle-même : seul le kiné décide.

## Contexte

Projet développé pendant le Build Challenge (Unaite, MWM, Apple, ⌘+F), les 15 et 16 octobre 2026. Équipe de deux développeurs. Objectif : une app fonctionnelle et un build soumis sur App Store Connect à la fin du deuxième jour. Le temps est très limité : privilégier ce qui marche et se démontre.

**Esprit du hackathon :** le Build Challenge vise à tirer parti de l'écosystème Apple. Quand une technologie Apple répond au besoin (Foundation Models, Vision, HealthKit, Liquid Glass, Apple Watch…), la préférer à une solution générique et la mettre en valeur dans la démo. Proposer les technologies Apple qui enrichiraient l'app, mais ne pas les ajouter sans validation. Le parcours principal de la démo reste prioritaire : une technologie de plus ne doit pas le mettre en danger.

**Apple Watch :** prévue dans un second temps, dans une cible watchOS séparée ; usage à définir. Ne rien construire pour la montre tant que cette cible n'existe pas.

## Priorités (ordre de construction)

Ne pas passer à l'étape suivante tant que la précédente ne fonctionne pas de bout en bout.

1. **Séance guidée** : caméra + Vision + comptage des répétitions sur un exercice codé en dur. C'est le cœur de la démo.
2. **Lecture de la feuille** : photo → programme structuré, avec écran de vérification.
3. **Douleur + historique** : saisie 0–10 en fin de séance, stockage SwiftData.
4. **Rapport hebdo** : génération et partage.
5. **Bonus** : App Intents et widget, HealthKit, StoreKit, finitions Liquid Glass.

Prévoir des données de démo (un programme et quelques séances pré-remplies) pour pouvoir montrer le rapport sans attendre une semaine.

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
| Partage du rapport | ShareLink (PDF généré sur l'appareil) |
| Abonnement | StoreKit 2 (à confirmer, voir Modèle économique) |
| Traductions | String Catalogs (`Localizable.xcstrings`) |

## Interface

Tout ce qui concerne l'interface (écrans, autorisations, interface adaptative, Liquid Glass, haptiques, accessibilité, traduction, App Intents) est dans `INTERFACE.md`. Le lire avant de toucher à une vue.

## Règles techniques

- **Tout reste sur l'appareil.** Aucune image, vidéo ou donnée de santé n'est envoyée sur un serveur. Seul le rapport hebdo part au kiné, sur action explicite du patient, via la feuille de partage système.
- **Foundation Models :** toujours vérifier la disponibilité du modèle avant de l'appeler et gérer proprement le cas où l'appareil n'est pas compatible. Solution de repli : saisie manuelle du programme. Utiliser la génération guidée (`@Generable`) pour obtenir directement des structures Swift.
- **Siri AI n'est pas disponible dans l'Union européenne** avec iOS 27 : ne construire aucune fonctionnalité dessus.
- **Séparer la logique de l'interface :** l'analyse des mouvements et la lecture de la feuille ne dépendent pas de SwiftUI. Elles doivent pouvoir être testées sans écran.
- **Concurrence Swift 6 :** mode strict activé. Le traitement des images caméra et Vision se fait hors du thread principal ; seule la mise à jour de l'interface passe par `@MainActor`.

## Sécurité du patient

- Si la douleur saisie est élevée (≥ 7 par défaut, à valider avec un kiné), afficher un message calme et non bloquant : « Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné. » Pas d'alerte qui empêche d'utiliser l'app.
- Ces séances sont signalées dans le rapport hebdo pour que le kiné les voie. C'est lui qui décide de la suite.
- Les corrections de mouvement restent des conseils (« monte un peu plus le bras »), jamais des consignes médicales.

## Soumission App Store

- Chaînes d'autorisation dans Info.plist : caméra, photothèque, HealthKit (lecture et écriture), avec un texte clair expliquant l'usage.
- Capacité HealthKit activée dans la cible.
- Privacy manifest (`PrivacyInfo.xcprivacy`) déclarant les données collectées : aucune donnée envoyée hors de l'appareil.
- Avertissement dans l'app : Rebond ne remplace pas l'avis d'un professionnel de santé.

## Modèle économique

Non établi. Piste envisagée : paiement côté kiné.
Tant que ce n'est pas tranché, ne pas construire de paywall bloquant le parcours de démo.

## Conventions de code

- Code, noms de types et commentaires : en anglais.
- Interface : en français par défaut, traduite via le String Catalog.
