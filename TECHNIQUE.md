# Rebond – architecture technique

Document de travail pour l'équipe. Le contexte produit est dans `CLAUDE.md`, l'interface dans `INTERFACE.md`.

## En bref

- App iPhone, SwiftUI, iOS 27.0 minimum, Swift 6.4 en concurrence stricte.
- Frameworks Apple uniquement, aucune dépendance tierce.
- Tout est traité sur l'appareil, aucun serveur.
- La logique (lecture de la feuille, analyse des mouvements) est séparée de l'interface et testable sans écran.

## Stack

| Besoin | Framework |
|---|---|
| Lecture de la feuille d'exercices | Foundation Models (modèle embarqué, entrée d'image, génération guidée `@Generable`) |
| Caméra | AVFoundation |
| Posture, angles, répétitions | Vision (body pose 2D, 3D si le temps le permet) |
| Stockage | SwiftData |
| Enregistrement des séances | HealthKit (bonus) |
| Rapport | PDF généré sur l'appareil, partagé via `ShareLink` |
| Consignes audio | AVSpeechSynthesizer |
| Intégration système | App Intents + WidgetKit (bonus) |
| Abonnement | StoreKit 2 (en attente du modèle économique) |
| Traductions | String Catalog |

## Organisation du projet

```
Rebond/
├── App/                 point d'entrée, navigation
├── Models/              modèles SwiftData
├── Catalog/             catalogue des exercices connus et leurs règles d'analyse
├── SheetReader/         photo → programme (Foundation Models), sans SwiftUI
├── Motion/              caméra, Vision, angles, comptage, sans SwiftUI
├── Report/              calcul des stats hebdo et génération du PDF
├── Health/              HealthKit
├── Intents/             App Intents
├── Views/               écrans SwiftUI
└── Resources/           String Catalog, données de démo
```

## Point clé : le catalogue d'exercices

La caméra ne peut pas analyser un exercice qu'elle ne connaît pas. On maintient donc un petit catalogue d'exercices connus, chacun avec ses règles d'analyse :

- l'articulation à suivre (ex. genou pour le squat : angle hanche – genou – cheville) ;
- l'angle de départ et l'angle cible ;
- le type : répétitions ou maintien chronométré (gainage) ;
- les corrections possibles (« descends encore un peu »).

Le rôle de Foundation Models est de **faire correspondre chaque exercice de la feuille à une entrée du catalogue**, et d'en extraire séries, répétitions et fréquence.

Un exercice hors catalogue reste utilisable en mode simple : minuteur et comptage manuel, sans analyse caméra.

Pour le hackathon : 3 à 5 exercices bien réglés valent mieux que 20 approximatifs. Proposition : squat, pont fessier, gainage, élévation latérale du bras, extension du genou assis.

## Lecture de la feuille (SheetReader)

1. Vérifier la disponibilité du modèle (`SystemLanguageModel.default.availability`). S'il n'est pas disponible : saisie manuelle du programme.
2. Envoyer la photo au modèle avec une consigne et un type `@Generable` qui décrit le programme attendu.
3. Le modèle renvoie directement une structure Swift : liste d'exercices (identifiant du catalogue ou « inconnu », nom lu, séries, répétitions ou durée), fréquence par semaine.
4. L'écran de vérification affiche le résultat ; le patient corrige avant d'enregistrer.

Risque : écriture manuscrite mal lue. Parades : écran de vérification obligatoire, et une feuille de démo préparée et testée à l'avance.

## Analyse des mouvements (Motion)

Chaîne de traitement :

```
Caméra (AVFoundation)
  → images, hors thread principal
  → Vision : points du corps (articulations + confiance)
  → calcul de l'angle de l'articulation suivie
  → lissage (moyenne glissante sur quelques images)
  → machine à états : repos → descente → bas atteint → remontée → +1 répétition
  → événements vers l'interface : compteur, correction, fin de série
```

Règles :
- **Seuils avec hystérésis** : une répétition compte quand l'angle passe sous le seuil bas puis repasse au-dessus du seuil haut. Évite les doubles comptages.
- **Points peu fiables ignorés** : en dessous d'un niveau de confiance, on n'actualise pas.
- **Correction** : si la remontée commence avant l'angle cible, on affiche la consigne et on ne compte pas la répétition (ou on la compte comme incomplète, à décider).
- **Amplitude** : on garde l'angle extrême atteint à chaque répétition, c'est ce qui alimente le « +12° » du rapport.
- **Performance** : pas besoin d'analyser chaque image, 15 par seconde suffisent.
- **Placement du téléphone** : un écran d'aide avant la séance (téléphone posé à 2–3 m, corps entier visible, de profil pour le squat).

Tout ce module se teste sans caméra en lui injectant des séries d'angles enregistrées.

## Modèle de données (SwiftData)

```
Program
  - createdAt
  - sessionsPerWeek
  - exercises: [PlannedExercise]

PlannedExercise
  - catalogId (ou nil si hors catalogue)
  - displayName
  - sets, reps   (ou holdSeconds pour un maintien)
  - order

Session
  - date
  - pain (0–10)
  - results: [ExerciseResult]

ExerciseResult
  - plannedExercise
  - completedReps
  - incompleteReps
  - bestAngle (amplitude)
```

## Rapport hebdo (Report)

- Calculé à partir des `Session` de la semaine : séances faites / prévues, répétitions, évolution de l'amplitude, évolution de la douleur.
- Séances avec douleur ≥ 7 signalées.
- PDF généré sur l'appareil, envoyé uniquement quand le patient appuie sur « Envoyer à mon kiné » (feuille de partage : mail, Messages…).
- Données de démo pré-remplies pour montrer un rapport complet pendant la présentation.

## Bonus, dans l'ordre

1. **App Intents** : « Démarrer ma séance » dans Raccourcis, Spotlight et le centre de contrôle ; widget « Prochaine séance ».
2. **HealthKit** : enregistrer chaque séance comme entraînement.
3. **Body pose 3D** : angles plus fiables quand le patient n'est pas parfaitement de profil.
4. **StoreKit** : seulement quand le modèle économique est décidé.

## Répartition proposée

| Dev A – moteur | Dev B – app |
|---|---|
| Caméra + Vision | Navigation et écrans |
| Calcul des angles, comptage, corrections | SwiftData + données de démo |
| Catalogue d'exercices et réglages | Lecture de la feuille (Foundation Models) + écran de vérification |
| Écran de séance (avec B) | Rapport hebdo + PDF |
| | Autorisations, String Catalog, soumission App Store |

Point de synchro : l'interface entre les deux, c'est le catalogue (`catalogId`) et les événements émis par Motion (répétition comptée, correction, fin de série). À définir ensemble au début du jour 1.

## Avant le 15 octobre

- [ ] Compte développeur actif, équipe de signature configurée sur les deux Mac.
- [ ] Identifiant d'app créé, fiche App Store Connect créée (nom, icône provisoire).
- [ ] Projet Xcode initialisé et partagé (dépôt Git), capacité HealthKit ajoutée.
- [ ] Vérifier sur un vrai iPhone que Foundation Models est disponible et lit une feuille test.
- [ ] Feuille d'exercices de démo imprimée.
- [ ] Un premier build envoyé sur TestFlight pour valider la chaîne de soumission.

## Questions ouvertes

- Une répétition incomplète compte-t-elle ?
- Langues cibles de la traduction.
- Modèle économique (paiement côté kiné ou abonnement patient).
- Usage de l'Apple Watch (plus tard, cible séparée).
