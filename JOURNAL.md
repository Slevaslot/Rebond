# Journal de développement – branche `technique`

Ce document retrace ce qui a été construit sur la branche `technique`, les décisions prises en cours de route et pourquoi, pour que l'autre développeur puisse reprendre rapidement. Le contexte produit et les règles du projet sont dans `CLAUDE.md`, l'organisation technique prévue dans `TECHNIQUE.md`.

## Contexte

- App iPhone de rééducation à domicile (squat en premier exercice), interface en français, frameworks Apple uniquement, tout reste sur l'appareil.
- Build Challenge des 15 et 16 octobre 2026 : priorité à ce qui marche et se démontre.
- Ordre de construction suivi : séance guidée d'abord (cœur de la démo), puis lecture de la feuille, douleur et historique, rapport hebdo.
- Testé sur un iPhone 17 branché au Mac (le simulateur n'a pas de caméra : la séance ne peut être testée que sur un appareil).

## Organisation du code

| Dossier | Contenu |
|---|---|
| `Catalog/` | `CatalogExercise` : règles d'un exercice (articulations suivies, profondeur cible, poses du pictogramme). Squat seulement. |
| `Motion/` | Logique sans SwiftUI : `PoseAnalyzer` (Vision), `RepCounter` (comptage et corrections), `GuidePlacement` (placement dans la silhouette), `HandGestures` (gestes de la main), `BackgroundBlur` (flou), `Coach` (voix), `MotionSession` (caméra et orchestration). |
| `Models/` | SwiftData : `Program`, `PlannedExercise`, `Session`, `ExerciseResult`, édition du brouillon de programme. |
| `SheetReader/` | Lecture de la feuille d'exercices avec Foundation Models (entrée d'image, `@Generable`), vérification de disponibilité, repli en saisie manuelle. |
| `Report/` | Rapport hebdo (`WeeklyReport`) et PDF (`ReportPDF`, partagé avec `ShareLink`). |
| `Resources/` | Données de démo, `PrivacyInfo.xcprivacy`, `Localizable.xcstrings`. |
| `Views/` | Accueil, séance (`SessionView`), pictogramme (`MovementGuide`), squelette, jauge, programme, historique, rapport, douleur. |

Swift 6 en concurrence stricte (`SWIFT_VERSION 6.0`), isolation MainActor par défaut : les types de logique sont `nonisolated`, le traitement des images se fait sur la file vidéo.

## Parcours d'une séance

1. **Placement.** Une silhouette fixe (pictogramme) indique où se mettre ; elle se cale sur les pieds du patient. Elle devient jaune quand il est proche, verte quand il est aligné. Une consigne courte en haut (« Reculez un peu », « Décalez-vous vers la gauche »…) est aussi dite à voix haute.
2. **Mesure du repos.** Le patient reste immobile : la position debout de référence est mesurée.
3. **Démonstration.** Le pictogramme fait le mouvement une fois en grand, la caméra est floutée et assombrie (« Regardez d'abord le mouvement »). Pas de compte à rebours.
4. **Série.** Le pictogramme rétrécit progressivement jusqu'à une vignette (déplaçable, redimensionnable). « C'est parti ! », le comptage démarre.
5. **Fin.** « Série terminée », puis Recommencer ou Continuer (douleur 0–10, enregistrement).

### Pendant la série

- **Agrandir le modèle** (double tap sur la vignette, glisser vers le haut sur la tige des AirPods, ou geste de la main) : le modèle repasse en grand, la caméra est floutée, rien n'est compté. On le remet en vignette (tap, pincement, glisser vers le bas, geste) et « À vous », le comptage reprend.
- **Pause** (bouton, appui sur les AirPods, ou paume levée) : seule la barre du haut reste, avec un gros bouton pause au centre sur l'image floutée. À la reprise, le modèle est toujours en vignette.
- **Corps perdu** : si la caméra ne voit plus le patient pendant environ 1,5 s, la silhouette de placement revient avec la même consigne. Rien n'est compté tant qu'il n'est pas revenu dedans ; les répétitions déjà faites sont gardées.
- **Après deux mouvements refusés d'affilée**, le modèle montre le mouvement en grand pendant 4 s.

## Détection du mouvement

- **Vision 2D** (`VNDetectHumanBodyPoseRequest`), 15 analyses par seconde, caméra frontale 720p en miroir. Si plusieurs personnes sont visibles, le patient est la plus grande à l'écran.
- La 3D a été essayée puis abandonnée au profit de la 2D, plus fiable sur nos vidéos.
- **Profondeur** = descente des hanches divisée par la longueur du buste debout. Cible : **0,6 buste** (squat partiel, adapté aux patients âgés ; la cible plus exigeante était jugée trop stricte).
- **Machine à états** : calibrage → repos → descente → bas atteint → remontée. Une remontée avant la cible compte une répétition incomplète ; une répétition trop rapide (< 1,2 s) déclenche « plus lentement ».
- **Mouvements rejetés** : fentes, pas, squat sumo, fentes latérales, grenouille, buste penché, une seule jambe pliée, pieds qui bougent, genoux qui rentrent. Les limites dépendent de la vue (face ou profil, détectée par la largeur des hanches). Un défaut doit persister 3 images avant d'être signalé.
- Les corrections s'affichent en rouge sur le squelette et sont dites à voix haute. Ce sont des conseils, jamais des consignes médicales.

### Résultats des tests (vidéos rejouées dans le code de l'app)

- Vidéos enregistrées par l'équipe : les bons squats sont comptés, les faux mouvements (fente, grenouille, buste penché, pas) sont rejetés.
- Jeu de données public UI-PRMD (Kinect, squats corrects et incorrects) : 85 à 91 % des bons squats comptés, 26 à 39 % des mauvais encore comptés. Les chevilles Kinect sont peu fiables et sont ignorées dans ces tests.

## Pictogramme (modèle du mouvement)

- Dessiné en `Canvas`, un seul contour : tête ronde, cou, buste de la largeur des jambes aux coins arrondis, bras et jambes d'épaisseur constante.
- En descendant, les coudes se plient et les mains se rejoignent devant la poitrine, comme un vrai squat.
- Plusieurs versions ont été essayées (bonhomme bâton, épaules, bras écartés…) ; celle-ci a été retenue pour sa simplicité.
- Toujours dessiné à sa taille maximale puis réduit (`scaleEffect`) pour un rétrécissement fluide ; l'épaisseur du trait est animée avec la taille pour ne pas sauter pendant le zoom.
- « Réduire les animations » est respecté (le pictogramme reste immobile).

## Flou et vie privée

- `VNGeneratePersonInstanceMaskRequest` : seul le patient reste net, le reste de la pièce et **les autres personnes** sont floutés. Masque élargi et adouci pour ne pas coller à la silhouette.
- Quand personne n'est détecté, toute l'image est floutée.
- Aucune image ne quitte l'appareil.

## Commandes à distance

- **AirPods – appui** : pause / reprise. Rebond devient l'app « en cours de lecture » pendant la séance ; chaque commande reçue (lecture, pause, bascule) inverse l'état, car iOS envoie parfois « lecture » pour mettre en pause.
- **AirPods – glisser sur la tige** : vers le haut agrandit le modèle, vers le bas le réduit. iOS ne permet pas de lire ce geste directement : l'app observe le changement de volume. Limites : le volume change vraiment, rien ne se passe au volume maximum ou minimum, les boutons de volume de l'iPhone ont le même effet.
- **Gestes de la main** (Vision, `VNDetectHumanHandPoseRequest`) — une seule main levée à hauteur d'épaule, l'autre baissée :
  - paume ouverte tenue environ 0,6 s : pause / reprise ;
  - pouce et index collés puis écartés : agrandir le modèle ;
  - pouce et index écartés puis pincés : le remettre en vignette.
- Garde-fous des gestes : les mains ne sont analysées que si un poignet est levé (pendant le squat, elles restent à la poitrine) ; une seule main levée (un exercice des deux bras paumes ouvertes ne met pas en pause) ; seules les mains au bout des poignets du patient comptent ; chaque position doit être tenue au moins deux images ; après un zoom, la main ouverte ne met pas en pause tant qu'elle n'a pas été baissée.
- Essais abandonnés : écarter les deux mains comme sur Apple Vision Pro (mouvement trop grand), signe « OK » (pas naturel), pincement seul (déclenché en parlant avec la main).
- Résultat sur nos 9 vidéos : aucun geste déclenché par erreur. Les gestes eux-mêmes restent à valider devant la caméra.

## Voix

- `AVSpeechSynthesizer`, la voix française de meilleure qualité installée est choisie automatiquement (Premium > Améliorée > défaut, région de l'utilisateur en priorité).
- Les voix Premium sont gratuites mais à télécharger sur chaque iPhone : Réglages > Accessibilité > Contenu énoncé > Voix > Français (ex. Audrey). Sans elles, l'app prend la voix de base.
- Piste si la voix n'est pas assez naturelle : enregistrer la quarantaine de phrases du coach avec une vraie voix et les jouer avec AVFoundation.
- Session audio `.playback` / `.spokenAudio` : audible même en mode silencieux, interrompt la musique pendant la séance.

## Reste du parcours

- **Lecture de la feuille** : photo → Foundation Models (vérification de disponibilité du modèle et de l'entrée d'image) → programme structuré, écran de vérification et d'édition avant enregistrement. Repli : saisie manuelle.
- **Douleur** 0–10 en fin de séance ; à partir de 7, message calme et non bloquant invitant à en parler au kiné.
- **Historique** des séances (SwiftData).
- **Rapport hebdo** : exercices faits, répétitions, amplitude, douleur, séances à douleur élevée signalées ; PDF généré sur l'appareil et partagé via la feuille de partage.
- **Données de démo** pour montrer le rapport sans attendre une semaine ; bouton de réinitialisation.
- `PrivacyInfo.xcprivacy` : aucune donnée envoyée hors de l'appareil.

## Installer sur l'iPhone

L'iPhone doit être branché, déverrouillé, et l'équipe de signature choisie dans Xcode (réglage local, non commité). Ensuite, dans Xcode, choisir l'iPhone comme destination et lancer (⌘R), ou en ligne de commande :

```bash
xcodebuild -scheme Rebond -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

## Points ouverts

- Valider les gestes de la main et le glisser sur la tige des AirPods en conditions réelles ; ajuster l'écart pouce-index demandé si le geste passe mal à distance.
- Décider si l'on garde le glisser sur la tige (il change le volume).
- Le bouton « Terminer la série » peut chevaucher le bas de la silhouette quand le corps est perdu.
- Seuil de douleur élevée (7) à valider avec un kiné.
- Prochaines étapes de `CLAUDE.md` : HealthKit, App Intents et widget, cible Apple Watch (rien n'est construit pour la montre).
