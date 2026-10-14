# Rebond – contexte projet

## Le produit

Rebond est une app iPhone de rééducation à domicile.

1. Le patient scanne la feuille d'exercices donnée par son kiné (dessins, texte imprimé ou manuscrit).
2. L'IA embarquée la transforme en programme structuré : exercices, séries, répétitions ou durée, fréquence. Le patient vérifie et corrige le programme avant de l'enregistrer.
3. Pendant chaque séance, la caméra suit le corps du patient, compte les répétitions et donne des conseils de mouvement en temps réel.
4. En fin de séance, le patient indique son niveau de douleur (0 à 10).
5. Le patient envoie à son kiné un bilan hebdomadaire (régularité, répétitions, amplitude, douleur), pour que le kiné ajuste le programme. Un rappel l'y invite chaque semaine.

**Côté kiné (Rebond Pro, payant)** : dans la même app, le kiné active l'espace kiné (Réglages › « Je suis kiné », ou en ouvrant un bilan `.rebond`). Un onglet « Kiné » s'ajoute et devient l'onglet affiché au lancement ; il permet de prescrire un programme par QR code (le patient le scanne avec l'appareil photo) et de suivre ses patients à partir des bilans reçus (fichier `.rebond`). Aucun serveur : les données passent directement du patient au kiné.

**Problème résolu :** le kiné ne sait pas si un traitement échoue parce qu'il est inefficace ou parce que le patient a sauté ou mal fait ses exercices.

**Ce que Rebond n'est pas :** un dispositif médical. L'app ne pose pas de diagnostic, ne mesure rien à des fins cliniques et ne modifie jamais le programme elle-même : seul le kiné décide. Dans l'app comme sur la fiche App Store, on parle de « conseils » et de « suivi », jamais de « traitement » ou de « correction médicale ».

## Contexte

Projet développé pendant le Build Challenge (Unaite, MWM, Apple, ⌘+F), les 15 et 16 octobre 2026. Équipe de deux développeurs. Objectif : une app fonctionnelle et un build soumis sur App Store Connect à la fin du deuxième jour. Le temps est très limité : privilégier ce qui marche et se démontre.

**Esprit du hackathon :** tirer parti de l'écosystème Apple. Quand une technologie Apple répond au besoin, la préférer à une solution générique et la mettre en valeur dans la démo. Proposer les technologies Apple qui enrichiraient l'app, mais ne pas les ajouter sans validation. Le parcours principal de la démo reste prioritaire : une technologie de plus ne doit pas le mettre en danger.

**Apple Watch :** hors périmètre du hackathon. Ne rien construire pour la montre.

## Priorités (ordre de construction)

Ne pas passer à l'étape suivante tant que la précédente ne fonctionne pas de bout en bout sur un vrai iPhone.

1. **Séance guidée** : caméra + Vision + comptage sur le squat, du placement au résumé de fin de série. C'est le cœur de la démo.
2. **Lecture de la feuille** : scan → programme structuré → écran de vérification → enregistrement.
3. **Séance complète et douleur** : enchaîner les exercices du programme (caméra ou comptage manuel, répétitions ou maintien chronométré), saisie de la douleur, stockage SwiftData.
4. **Progrès et rapport** : graphiques, PDF, partage.
5. **Deuxième exercice suivi par la caméra** : élévation latérale des bras.
6. **Bonus** : rappels (notifications locales), App Intents et widget, finitions Liquid Glass, HealthKit.

Prévoir des données de démo (un programme et quelques séances pré-remplies) pour montrer le rapport sans attendre une semaine.

## Décisions prises

| Question | Décision |
|---|---|
| Répétition incomplète | Comptée à part, elle ne compte pas dans l'objectif de la série. Le kiné voit les deux nombres. |
| Mesure du mouvement | Chaque exercice du catalogue définit sa propre mesure (déplacement normalisé par la longueur du buste, ou angle d'articulation). L'amplitude est exprimée en % de l'objectif. |
| Exercices suivis par la caméra | Squat, puis élévation latérale des bras. Tous deux debout et de face : même placement du téléphone pour toute la séance. Les autres exercices sont en comptage manuel ou au minuteur. |
| Semaine du rapport | Les 7 derniers jours, dates exactes affichées. |
| Seuil de douleur élevée | 7, paramétrable, à valider avec un kiné. |
| Langues | Français (source) et anglais. |
| Modèle économique | Le patient ne paie jamais. Kiné : offre gratuite (tout en local, 3 patients suivis) et Rebond Pro (patients illimités, tout en local). Voir `BUSINESS.md`. |
| Serveur | Aucun. La version connectée de démo (`Server/`, `DemoServer`) a été supprimée : les bilans et les programmes passent seulement par le fichier `.rebond` et le QR code. |
| Espace kiné | Un onglet « Kiné » de plus (pas une app à part) : le kiné garde l'accès à l'app patient. Activé dans Réglages ou en ouvrant un bilan, il reste activé d'un lancement à l'autre et l'app s'ouvre dessus. Patients de démo pour la présentation. |
| Tutoriel | Aucun écran d'accueil ni tutoriel : la séance guide le patient à la voix. |
| Commandes à distance | Geste de la main (paume ouverte = pause) doublé d'un bouton. Pas d'AirPods, pas de boutons de volume. |
| HealthKit | Seulement s'il est réellement utilisé dans le build soumis. Ne pas déclarer la capacité avant. |
| Icône | Format Icon Composer (`AppIcon.icon` : fond en dégradé + symbole en calque Liquid Glass), compatible avec les modes sombre, teinté et transparent d'iOS. |
| Traductions | String Catalog en français (pluriels compris). Les autres langues sont générées à la fin avec « Generate Translations » d'Xcode, puis relues. |

## Environnement

- Xcode 27.1, Swift 6.4 (mode de langage Swift 6), SDK iOS 27.1
- Cible de déploiement : iOS 27.0, iPhone uniquement
- SwiftUI uniquement
- Frameworks Apple natifs uniquement, aucune dépendance tierce sans validation
- Isolation `MainActor` par défaut : les types de logique (Motion, SheetReader, Report) sont marqués `nonisolated`

## Frameworks utilisés

| Besoin | Framework |
|---|---|
| Scan de la feuille | VisionKit (scanner de documents), PhotosUI (`PhotosPicker`) |
| Lecture de la feuille | Foundation Models (modèle embarqué, entrée d'image, `@Generable`) |
| Caméra | AVFoundation |
| Posture, répétitions, gestes, flou | Vision (body pose 2D, hand pose, masque de personne) |
| Voix du coach | AVSpeechSynthesizer |
| Stockage local | SwiftData |
| Graphiques | Swift Charts |
| Rapport | PDF généré sur l'appareil (`ImageRenderer`), partagé via `ShareLink` |
| Rappels | UserNotifications (notifications locales) |
| Abonnement kiné | StoreKit 2 (`SubscriptionStoreView`, codes d'offre) |
| Prescription par QR code | Core Image (QR), lien `rebond://programme` |
| Intégration système (bonus) | App Intents, WidgetKit |
| Enregistrement des séances (bonus) | HealthKit |
| Traductions | String Catalogs (`Localizable.xcstrings`) |

## Interface

Tout ce qui concerne l'interface (structure, séance, scan, autorisations, Liquid Glass, accessibilité, rédaction, traduction, App Intents) est dans `INTERFACE.md`. Le lire avant de toucher à une vue.

## Règles techniques

- **Tout reste sur l'appareil.** Aucune image, vidéo ou donnée de santé n'est envoyée sur un serveur. Seul le rapport part au kiné, sur action explicite du patient, via la feuille de partage système.
- **Foundation Models :** toujours vérifier la disponibilité du modèle et sa capacité à lire une image avant de l'appeler. Repli : saisie manuelle du programme. Génération guidée (`@Generable`) pour obtenir directement des structures Swift.
- **Siri AI n'est pas disponible dans l'Union européenne** avec iOS 27 : ne construire aucune fonctionnalité dessus.
- **Séparer la logique de l'interface :** l'analyse des mouvements, la lecture de la feuille et le calcul du rapport ne dépendent pas de SwiftUI et sont couverts par la cible de tests (séries de mesures enregistrées, sans caméra).
- **Concurrence Swift 6 :** mode strict. Le traitement des images caméra et Vision se fait hors du thread principal ; seule la mise à jour de l'interface passe par `@MainActor`.
- **Ne détourner aucun contrôle système** (boutons de volume, commandes AirPods) : HIG *Playing audio* et App Review 2.5.9.

## Sécurité du patient

- Si la douleur saisie est élevée (≥ 7 par défaut), afficher un message calme et non bloquant : « Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné. » Pas d'alerte qui empêche d'utiliser l'app.
- Ces séances sont signalées dans le rapport pour que le kiné les voie. C'est lui qui décide de la suite.
- Les conseils de mouvement restent des conseils (« Gardez le buste droit »), jamais des consignes médicales.
- Quand la caméra voit mal le patient, on ne compte rien et on ne corrige rien plutôt que de donner une information fausse.

## Soumission App Store

- Chaîne d'autorisation caméra dans Info.plist, avec un texte clair sur l'usage (scan et séance). `PhotosPicker` ne demande pas d'autorisation. HealthKit seulement s'il est utilisé.
- Privacy manifest (`PrivacyInfo.xcprivacy`) à jour, y compris les API à justification (`UserDefaults`, dates de fichiers…) si elles sont utilisées.
- Étiquettes de confidentialité App Store Connect : « Aucune donnée collectée ».
- URL de politique de confidentialité (obligatoire), même courte : à publier, puis mettre à jour `AppLinks.privacyPolicy`.
- Produits `rebond.pro.monthly` et `rebond.pro.yearly` à créer dans App Store Connect (groupe « Rebond Pro »). Le fichier `Rebond.storekit` permet de tester l'achat depuis Xcode.
- Avertissement dans l'app : Rebond ne remplace pas l'avis d'un professionnel de santé.
- Icône réalisée avec Icon Composer.
- Une seule équipe de signature propriétaire de l'identifiant d'app.

## Modèle économique

B2B, détaillé dans `BUSINESS.md` : l'app patient est entièrement gratuite, sans aucun écran payant ; l'espace kiné demande l'abonnement Rebond Pro. Les builds de développement ont un interrupteur « Débloquer Pro (démo) ».

## Conventions de code

- Code, noms de types et commentaires : en anglais.
- Interface : en français par défaut (vouvoiement), traduite via le String Catalog.
