# Rebond – architecture technique

Document de travail pour l'équipe. Le contexte produit et les décisions sont dans `CLAUDE.md`, l'interface dans `INTERFACE.md`, l'historique de ce qui a été essayé dans `JOURNAL.md`.

## En bref

- App iPhone, SwiftUI, iOS 27.0 minimum, Swift 6 en concurrence stricte, isolation `MainActor` par défaut.
- App Apple Watch compagnon (watchOS 27.0) et ses complications, reliées à l'iPhone par WatchConnectivity.
- Frameworks Apple uniquement, aucune dépendance tierce.
- Tout est traité sur l'appareil, aucun serveur.
- La logique (lecture de la feuille, analyse des mouvements, rapport) est séparée de l'interface et testée sans écran.

## Point de départ

Le moteur de séance (`Motion/`) a été prototypé et validé avant le hackathon : placement, calibrage, comptage du squat, rejet des faux mouvements, flou de la pièce, voix, geste « paume = pause ». Il est **conservé**. Tout le reste (navigation, scan, programme, séance complète, progrès, rapport) est construit selon ce document et `INTERFACE.md`, sans se caler sur le prototype.

## Organisation du projet

```
Rebond/
├── App/                 point d'entrée, onglets, routage
├── Models/              modèles SwiftData
├── Catalog/             exercices connus et leurs règles d'analyse
├── SheetReader/         scan → programme (Foundation Models), sans SwiftUI
├── Motion/              caméra, Vision, mesures, comptage, gestes, voix, sans SwiftUI
├── Workout/             enchaînement des exercices d'une séance (caméra, manuel, minuteur), sans SwiftUI
├── Report/              statistiques, données des graphiques, PDF
├── Reminders/           notifications locales
├── Store/               abonnement Rebond Pro (StoreKit 2)
├── Pro/                 rôle patient / kiné, transferts (lien du programme, fichier de bilan), synthèse d'un patient
├── Intents/             App Intents
├── Watch/               lien avec l'Apple Watch côté iPhone (WatchConnectivity)
├── Health/              enregistrement des séances dans Santé depuis l'iPhone
├── Views/               écrans SwiftUI, regroupés par onglet
└── Resources/           String Catalog, données de démo, PrivacyInfo
RebondTests/             tests (Swift Testing) : compteurs, séance, bilan, programme, montre
RebondWidgets/           widgets iPhone, Live Activity, bouton du Centre de contrôle
RebondWatch/             app Apple Watch : série en direct, haptique, entraînement HealthKit, Siri
RebondWatchWidgets/      complications et Smart Stack de la montre
Shared/                  compilé dans plusieurs cibles (exceptions dans le projet) : App Group, instantané
                         des widgets, protocole iPhone ↔ montre, types Santé, intents partagés
Rebond-Info.plist        schéma d'URL `rebond://` et type de fichier `.rebond`
Rebond.storekit          produits Rebond Pro pour les tests dans Xcode
```

## Le catalogue d'exercices

La caméra ne suit que les exercices qu'elle connaît. Chaque entrée du catalogue définit :

- **`id`** stable (`squat`, `lateral-raise`) : c'est le lien entre la feuille, le programme et le moteur ;
- **le type** : répétitions ou maintien chronométré ;
- **la mesure** suivie, l'une de :
  - `verticalDrop(joint:)` : descente d'une articulation divisée par la longueur du buste debout (squat : hanches) ;
  - `angle(a, vertex, b)` : angle entre trois articulations (élévation latérale : hanche – épaule – poignet) ;
- **l'objectif** (profondeur ou angle cible) et les seuils d'hystérésis ;
- **la vue attendue** (face) et les articulations qui doivent être visibles ;
- **les défauts surveillés** et leur consigne (« Gardez le buste droit ») ;
- **les poses du pictogramme** (repos et objectif).

Hackathon : **squat** (fait) puis **élévation latérale des bras**. Tous deux debout et de face : le téléphone ne bouge pas entre les deux. Tout autre exercice passe en comptage manuel (boutons + / −) ou au minuteur (maintien).

## Lecture de la feuille (SheetReader)

1. Capture : `VNDocumentCameraViewController` (VisionKit), ou `PhotosPicker` pour une photo existante.
2. Disponibilité : `SystemLanguageModel.default.availability` **et** capacité d'entrée d'image. Sinon : message adapté à la cause, puis saisie manuelle.
3. Appel du modèle avec des instructions et un type `@Generable` :

```
ProgramDraft
  - sessionsPerWeek: Int?          nil si la feuille ne le dit pas
  - exercises: [ExerciseDraft]

ExerciseDraft
  - name: String                   tel qu'écrit sur la feuille
  - kind: squat | lateralRaise | other
  - sets: Int?
  - reps: Int?                     pour un exercice en répétitions
  - holdSeconds: Int?              pour un maintien (gainage…)
```

   Les champs optionnels permettent de distinguer ce qui a été **lu** de ce qui sera **complété par défaut** (3 séances, 3 séries, 10 répétitions, 30 s) et signalé « À vérifier » à l'écran.
4. Conversion `ProgramDraft` → brouillon éditable (logique pure, testée), écran de vérification, enregistrement.

Risque : écriture manuscrite mal lue. Parades : scanner de documents (image redressée), écran de vérification obligatoire, feuille de démo imprimée et testée à l'avance.

## Analyse des mouvements (Motion)

```
Caméra frontale (AVFoundation), 720p, miroir
  → images sur la file vidéo, 15 analyses / s
  → Vision : points du corps + confiance ; mains seulement si un poignet est levé
  → mesure de l'exercice (descente ou angle), lissée sur quelques images
  → machine à états : calibrage → repos → aller → objectif atteint → retour → +1
  → événements vers l'interface (MainActor)
```

Événements émis (contrat entre le moteur et l'interface) :

```
placement(hint)        consigne de placement
calibrated             position de repos mesurée
repCompleted(count, amplitude)
repIncomplete(count)
correction(fault)      défaut en cours, déjà filtré (persiste ≥ 3 images)
bodyLost / bodyFound
gesture(.pause)
```

Règles :
- **Hystérésis** : une répétition compte quand la mesure franchit le seuil d'objectif puis revient sous le seuil de repos.
- **Confiance** : sous le seuil de confiance, on n'actualise rien ; après ~1,5 s sans corps, `bodyLost`.
- **Incomplète** : retour avant l'objectif → `repIncomplete`, non comptée dans la série.
- **Tempo** : répétition < 1,2 s → « Plus lentement » (au plus une fois toutes les 3 répétitions).
- **Amplitude** : extrême atteint à chaque répétition, en % de l'objectif ; la meilleure de la série est enregistrée.
- **Flou** : masque de personne (Vision), seul le patient reste net.
- **Tests** : le moteur reçoit des suites de points enregistrées depuis les vidéos de l'équipe ; les tests vérifient comptage, incomplètes et rejets.

## Séance (Workout)

Logique pure qui enchaîne les exercices du programme : pour chaque exercice, chaque série, choisit le mode (caméra si `catalogId` connu, sinon manuel ou minuteur), agrège les résultats, puis produit une `Session` après la saisie de la douleur. Une séance sans aucune répétition et de moins de 30 s n'est pas enregistrée sans confirmation.

## Modèle de données (SwiftData)

```
Program
  - createdAt
  - sessionsPerWeek
  - exercises: [PlannedExercise]   (cascade)

PlannedExercise
  - catalogId: String?             nil = hors catalogue
  - name
  - sets
  - reps: Int?  /  holdSeconds: Int?
  - order

Session
  - date
  - duration
  - pain (0–10)
  - results: [ExerciseResult]      (cascade)

ExerciseResult                     copie autonome, pas de lien vers PlannedExercise :
  - exerciseName                   l'historique survit au remplacement du programme
  - catalogId: String?
  - order
  - plannedReps / plannedSeconds
  - completedReps
  - incompleteReps
  - heldSeconds
  - amplitude: Double?             % de l'objectif, nil si non mesuré
```

## Progrès et rapport (Report)

- Fenêtre : les 7 derniers jours, dates exactes affichées.
- Calcul (logique pure, testée) : séances faites / prévues, répétitions complètes et incomplètes par exercice, amplitude première → dernière séance, douleur moyenne et évolution, séances à douleur ≥ 7.
- Graphiques Swift Charts partagés entre l'onglet Progrès et le PDF.
- PDF généré sur l'appareil, partagé via `ShareLink` uniquement quand le patient appuie sur « Envoyer à mon kiné ».

## Espace kiné (Rebond Pro)

- **Prescription** : `ProgramTransfer` (JSON compact, base64url) dans un lien `rebond://programme?d=…`, affiché en QR code (Core Image). Le patient le scanne avec l'appareil photo : `onOpenURL` ouvre l'écran de vérification.
- **Suivi** : le bilan partagé contient le PDF et un fichier `.rebond` (`ReportTransfer`, 6 dernières semaines, identifiant stable du patient). Ouvert avec Rebond, il crée ou met à jour un `TrackedPatient` ; le kiné voit le même résumé et les mêmes graphiques que le patient.
- **Activation** : `AppRole` (`UserDefaults`, clé `appRole`). Activé, il ajoute l'onglet `AppRouter.AppTab.physio`, sélectionné au lancement. Ouvrir un bilan l'active et ouvre la fiche du patient (`AppRouter.openPhysioSpace(patient:)`).
- **Synthèse** : `PatientOverview` (logique pure, testée) résume le dernier bilan : régularité, douleur (séances ≥ 7), répétitions, amplitude, et ce qui demande l'attention (douleur forte, peu de séances, bilan ancien) pour trier la liste.
- **Accès** : `ProStore` lit les droits StoreKit ; offre gratuite limitée à 3 patients (`TrackedPatient.importReport`), Rebond Pro illimité. L'app patient ne demande jamais l'abonnement.
- **Aucun serveur** : la version connectée de démo a été retirée. Programmes par QR code, bilans par fichier `.rebond`, sur geste du patient.

## Apple Watch

```
iPhone (caméra, comptage)                         Apple Watch
WorkoutView ── sessionStarted ──────────────────▶ startWatchApp → HKWorkoutSession (cœur, calories)
WorkoutLiveActivity ── set(WatchSetState) ──────▶ SetView + WatchHaptic → WKInterfaceDevice.play
PhoneWatchLink.command ◀── togglePause/nextSet ── boutons, Double Tap, Siri
                       ◀── recordingWorkout ───── la montre enregistrera l'entraînement
WorkoutView ── setsFinished, sessionEnded(saved) ▶ finishWorkout (Santé) ou discardWorkout
WidgetSync ── applicationContext(WidgetSnapshot) ▶ App Group de la montre → complications
```

- **Protocole** (`Shared/WatchLink.swift`, logique pure testée) : `PhoneMessage`, `WatchMessage`, `WatchSetState`, encodés en JSON sous une clé unique (`WatchCoding`). `WatchHaptic.feedback(from:to:)` choisit le seul retour à jouer.
- **Transport** : `sendMessage` pour le direct (seulement si la montre est joignable : une répétition en retard ne sert à rien) ; `transferUserInfo` pour le début, la fin et `recordingWorkout`, qui doivent arriver ; `updateApplicationContext` pour la séance du jour (seule la dernière compte).
- **Branchement** : `WorkoutLiveActivity` transmet chaque état à `PhoneWatchLink` : tout écran de série qui met à jour la Live Activity met aussi à jour la montre. Les commandes de la montre arrivent dans `WorkoutView` comme le menu Passer (`SkipRequest`) et un `pauseRequest` (environnement) lu par `SessionView` et `HoldSetView`.
- **Live Activity et Siri** : `ToggleSessionPauseIntent` et `NextSetIntent` (`LiveActivityIntent`, `Shared/SessionControlIntents.swift`) passent par le même chemin (`PhoneWatchLink.perform`).
- **Santé** : `HealthRecording.decide` (testé). La montre enregistre si elle a démarré son entraînement (`recordingWorkout`) ; sinon l'iPhone (`PhoneHealth`, `HKWorkoutBuilder`) si le patient l'a activé et que la séance dure au moins 20 s. Jamais de doublon.
- **Simulateur** : jumeler un iPhone et une montre (`xcrun simctl list pairs`), installer l'app iPhone, puis l'app de la montre (`Rebond.app/Watch/RebondWatch.app`). WatchConnectivity peut mettre une vingtaine de secondes à voir l'app de la montre installée (`isWatchAppInstalled`). La caméra n'existant pas en simulateur, tester avec un maintien chronométré ou un exercice en comptage manuel ; la montre simulée fournit une fréquence cardiaque factice.

## Astuces (TipKit)

- `Rebond/Tips/SessionTips.swift` : `SessionTips.configure()` (appelé dans `RebondApp.init`), `SiriPauseTip`, `WatchAppTip`. `RebondWatch/WatchTips.swift` : `WatchTips.configure()` (dans `RebondWatchApp.init`), `DoubleTapTip`. Chaque appareil a sa propre base TipKit.
- Règles : `SiriPauseTip` a un `#Rule` sur l'événement `sessionSaved` (donné par `WorkoutView.save`, au moins une séance enregistrée) ; l'instant (pause au bouton pendant la série, pas de montre qui enregistre la séance) est décidé par la vue (`SessionView`, `HoldSetView`). `WatchAppTip` dépend de `PhoneWatchLink.isWatchPaired` / `isWatchAppInstalled` et est invalidée quand l'app de la montre est installée. `DoubleTapTip` suit `statusUpdates` pour rendre la ligne « Série » dès qu'elle n'est plus affichable. `MaxDisplayCount` limite chacune ; `displayFrequency(.immediate)` parce que les écrans garantissent déjà une seule astuce à la fois.
- Démo et simulateur (Debug) : arguments de lancement `-RebondResetTips` (repart de zéro) et `-RebondShowAllTips` (ignore les règles TipKit, pas les conditions de la vue).

## Intégrations système

1. **Rappels** : notifications locales les jours de séance et rappel hebdomadaire du rapport.
2. **App Intents + widgets** : « Démarrer ma séance » (Raccourcis, Spotlight, centre de contrôle), « Séances de la semaine » (iPhone et montre), « Pause » et « Série suivante » (iPhone et montre), widgets « Séance du jour » et « Régularité ».
3. **Live Activity interactive** : boutons Pause et Série suivante.
4. **HealthKit** : chaque séance comme entraînement « renforcement fonctionnel », voir « Apple Watch ».

## Répartition

| Dev A – moteur | Dev B – app |
|---|---|
| Catalogue + élévation latérale | Onglets, navigation, accueil |
| Événements Motion, cible de tests | Scan (VisionKit) + SheetReader + vérification |
| Écran de séance caméra | Workout (enchaînement, manuel, minuteur), douleur |
| Réglage sur vidéos réelles | SwiftData, données de démo, Progrès, PDF |
| Icône (Icon Composer) | Autorisations, String Catalog, soumission |

Point de synchro : le catalogue (`catalogId`) et les événements Motion ci-dessus, figés le matin du jour 1.

## Avant le 15 octobre

- [ ] Relire le règlement du Build Challenge : le code écrit avant l'événement est-il autorisé ?
- [ ] Compte développeur actif ; **une** équipe propriétaire de l'app, ajoutée sur les deux Mac.
- [ ] Identifiant d'app créé (vérifier que `com.rebond.app` est libre, sinon en choisir un autre), fiche App Store Connect créée.
- [ ] URL de politique de confidentialité prête.
- [ ] `main` à jour avec la branche `technique`.
- [ ] Sur un vrai iPhone : Foundation Models lit une feuille test avec image.
- [ ] Feuille d'exercices de démo imprimée (squat, élévation latérale, gainage, un exercice manuscrit).
- [ ] Voix française Premium téléchargée sur l'iPhone de démo.
- [ ] Un premier build envoyé sur TestFlight pour valider la chaîne de soumission.

## Questions encore ouvertes

- Seuil de douleur et profondeur cible du squat à valider avec un kiné.
- Modèle économique (paiement côté kiné ou abonnement patient), après le hackathon.
- Apple Watch : compter sur la montre elle-même (accéléromètre) pour les exercices que la caméra ne suit pas, après le hackathon.
