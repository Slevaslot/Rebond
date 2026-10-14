# Rebond – architecture technique

Document de travail pour l'équipe. Le contexte produit et les décisions sont dans `CLAUDE.md`, l'interface dans `INTERFACE.md`, l'historique de ce qui a été essayé dans `JOURNAL.md`.

## En bref

- App iPhone, SwiftUI, iOS 27.0 minimum, Swift 6 en concurrence stricte, isolation `MainActor` par défaut.
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
├── Pro/                 rôle patient / kiné, transferts (lien du programme, fichier de bilan)
├── Intents/             App Intents
├── Views/               écrans SwiftUI, regroupés par onglet
└── Resources/           String Catalog, données de démo, PrivacyInfo
RebondTests/             tests (Swift Testing) : compteurs, séance, bilan, programme
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
- **Accès** : `ProStore` lit les droits StoreKit ; l'espace kiné demande l'abonnement, l'app patient jamais.

## Bonus, dans l'ordre

1. **Rappels** : notifications locales les jours de séance et rappel hebdomadaire du rapport.
2. **App Intents + widget** : « Démarrer ma séance » (Raccourcis, Spotlight, centre de contrôle), widget « Prochaine séance ».
3. **HealthKit** : enregistrer chaque séance comme entraînement (type « renforcement fonctionnel »).

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
- Usage de l'Apple Watch, après le hackathon.
