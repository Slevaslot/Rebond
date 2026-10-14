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

- **Agrandir le modèle** (double tap sur la vignette, ou geste de la main) : le modèle repasse en grand, la caméra est floutée, rien n'est compté. On le remet en vignette (tap, pincement, geste) et « À vous », le comptage reprend.
- **Pause** (bouton ou paume levée) : seule la barre du haut reste, avec un gros bouton pause au centre sur l'image floutée. À la reprise, le modèle est toujours en vignette.
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

- **AirPods (retiré)** : l'appui pour mettre en pause et le glisser sur la tige (détection par le volume) ont été essayés puis retirés. Détourner les contrôles audio est contraire aux HIG (*Playing audio*) et expose à un rejet (App Review 2.5.9).
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
- Session audio `.playback` / `.voicePrompt` avec `duckOthers` : audible même en mode silencieux, la musique est baissée pendant que le coach parle.

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

- Valider les gestes de la main en conditions réelles. Décision : ne garder que la paume ouverte pour la pause (voir `CLAUDE.md`).
- Le bouton « Terminer la série » peut chevaucher le bas de la silhouette quand le corps est perdu.
- Seuil de douleur élevée (7) à valider avec un kiné.
- Prochaines étapes de `CLAUDE.md` : HealthKit, App Intents et widget, cible Apple Watch (rien n'est construit pour la montre).

## Reconstruction (13 octobre, soir)

L'app a été reconstruite selon `CLAUDE.md`, `TECHNIQUE.md` et `INTERFACE.md`, en gardant le moteur de séance.

- **Moteur** : protocole `MovementCounter` ; le squat (`RepCounter`) et l'**élévation latérale des bras** (`ArmRaiseCounter`, angle bras-tronc, cible 80°, bras tendus, symétrie) partagent la même session caméra. Amplitude en % de l'objectif.
- **App patient** : onglets Aujourd'hui / Programme / Progrès, accueil en deux écrans, scanner de documents VisionKit, valeurs devinées par l'IA signalées « À vérifier », exercices en maintien avec minuteur, comptage manuel, douleur, résumé de fin de séance, graphiques Swift Charts, bilan PDF, rappels locaux, raccourci « Démarrer ma séance » (App Intents).
- **AirPods retirés** (contrôles audio détournés, contraire aux HIG). Gestes de la main conservés.
- **Modèle B2B** : l'app patient est gratuite ; l'espace kiné (Rebond Pro, StoreKit 2) permet de prescrire par QR code et de suivre les patients à partir de leurs bilans `.rebond`. Voir `BUSINESS.md`.
- **Icône** au format Icon Composer (modes sombre, teinté, transparent).
- **Tests** : cible `RebondTests` (Swift Testing), 18 tests sur les compteurs (mouvements synthétiques), la séance, le bilan et le programme.
- **À faire** : traductions (« Generate Translations » dans Xcode), produits App Store Connect, URL de confidentialité, tester l'élévation latérale devant la caméra.

## Nouveaux exercices suivis par la caméra (réglés sur UI-PRMD)

Logique commune dans `RepCycle` (repos → aller → objectif → retour, incomplètes, défaut confirmé sur 3 images, trop rapide). Rejeu des données Kinect avec perspective (téléphone à hauteur de hanche, 2,5 m) et ordre d'Euler corrigé (Z·X·Y) pour les jambes.

| Exercice | Mesure | Objectif | Bons comptés | Mauvais encore comptés |
|---|---|---|---|---|
| Assis-debout | montée des hanches au-dessus de l'assise | 0,6 buste | 100 % | 51 % |
| Élévation de la jambe tendue | montée du genou vers la hanche | 0,3 buste (cuisse ~55°) | 100 % | 69 % |
| Élévation latérale d'un bras | angle bras-tronc, un bras au choix | 110° | 99 % | 53 % |
| Élévation des bras en diagonale | angle bras-tronc | 90° | 100 % | 41 % |

À tester devant la caméra : chaise avec accoudoirs (assis-debout), genou plié pendant l'élévation de jambe, geste « paume ouverte » qui pourrait mettre en pause pendant les exercices à un bras. Pictogrammes de profil pour le squat, l'assis-debout et l'élévation de jambe.

## Le reste d'UI-PRMD : enjambement, fentes, épaule (14 octobre)

Les cinq mouvements restants du jeu de données ont été observés de face, en perspective (téléphone à hauteur de hanche, `PERSP=200/250/300`), avant d'écrire le moindre compteur. Résultats sur 100 bons et 100 mauvais mouvements chacun, à 2,5 m (les chiffres varient de 1 à 3 points entre 2 et 3 m).

| N° | Exercice (`id`) | Compteur | Mesure | Objectif | Bons comptés | Mauvais encore comptés |
|---|---|---|---|---|---|---|
| 2 | Montée de genou (`hurdle-step`) | `LegRaiseCounter(style: .bentKnee)` | montée du genou vers la hanche | 0,45 buste | 94 % | 41 % |
| 3 | Fente avant (`forward-lunge`) | `LungeCounter(direction: .forward)` | descente des hanches | 0,45 buste | 97 % | 54 % |
| 4 | Fente latérale (`side-lunge`) | `LungeCounter(direction: .side)` | décalage des hanches sur le côté | 0,4 buste | 98 % | 43 % |
| 9 | Rotation de l'épaule (`shoulder-rotation`) | `ShoulderRotationCounter` | descente du poignet vers le coude | 0,6 avant-bras | 100 % | 42 % |
| 8 | Extension d'épaule | — | **écartée** (voir plus bas) | — | 87 % au mieux | 37 % |

Les six exercices existants donnent exactement les mêmes chiffres avant et après ces ajouts.

### Montée de genou (enjambement, m2)

- **Mesure** : la même que l'élévation de jambe tendue (le genou monte vers la hanche, en longueurs de buste). Les bons enjambements montent le genou de 0,36 à 1,37 buste de face : ça se lit très bien.
- **Différence avec l'élévation de jambe** : le genou plié est attendu, le contrôle « jambe tendue » ne s'applique pas. À la place, le buste penché en avant (buste vu plus court que 88 % de sa longueur debout ; bons ≥ 93 %, mauvais jusqu'à 61 %) et penché sur le côté (0,2 ; bons ≤ 0,19, mauvais jusqu'à 0,6).
- **Seuils** : départ 0,16, retour 0,11, jambe d'appui qui plie (hanches qui descendent de plus de 0,15), comme l'élévation de jambe. Une jambe puis l'autre : le côté est choisi à chaque répétition.
- **Corrections** : « Montez le genou un peu plus haut », « Gardez le buste plus droit », « Gardez la jambe d'appui tendue ».
- **Objectif** : 0,45 (cuisse à environ 60°). 0,4 compte 98 % des bons mais 51 % des mauvais ; 0,5 tombe à 91 %.

### Fente avant (m3)

- **Mesure** : descente des hanches, comme le squat. De face, les deux genoux se superposent presque : le genou arrière qui descend ne se lit pas assez (écart des genoux de 0,13 seulement chez 10 % des bons).
- **Défauts** : buste penché sur le côté (0,25 ; bons ≤ 0,26, mauvais jusqu'à 0,8), buste penché en avant (moins de 75 % de sa longueur ; bons ≥ 78 %), descente sans plier un genou (aucun genou sous 145° au retour ; bons ≤ 125°).
- **Objectif** : 0,45 buste (les bons descendent de 0,43 à 0,98). 0,6 ne compte plus que 80 % des bons.
- **Limites** : un squat est aussi compté comme une fente avant. Serrer les seuils (0,22 / 0,78) ferait tomber les mauvais à 45 %, mais trop près des bons pour le bruit de Vision. Les mauvais restants sont surtout des défauts d'alignement du genou, invisibles en 2D de face sans chevilles fiables.

### Fente latérale (m4)

- **Mesure** : décalage des hanches sur le côté, quel que soit le côté. Les bons se décalent de 0,38 à 0,77 buste.
- **Défauts** : genou non plié (le genou le plus plié de la répétition doit passer sous 155° ; bons ≤ 148°, mauvais jusqu'à 176°), jugé au début du retour (il plie au plus profond, pas avant) ; buste penché sur le côté (0,5 ; bons ≤ 0,47, mauvais jusqu'à 1). Le buste penché en avant fait partie du mouvement (bons jusqu'à 56 % de sa longueur) : seul un écrasement sous 45 % est refusé.
- **Corrections** : « Allez un peu plus loin sur le côté », « Pliez le genou de la jambe qui avance », « Gardez le buste plus droit ».
- **Objectif** : 0,4 buste.

### Rotation de l'épaule (m9)

- **Ce que fait UI-PRMD** : la rotation en position « 90/90 », bras écarté à hauteur d'épaule, coude plié à 90°, avant-bras vertical qui bascule vers l'avant jusqu'à l'horizontale puis revient. **Ce n'est pas** la rotation coude collé au corps : celle-là n'a pas de données, elle reste en comptage manuel (la lecture de la feuille la classe en « autre »).
- **Mesure** : de face, l'avant-bras vertical est vu en entier ; en basculant vers la caméra, il raccourcit et le poignet descend à la hauteur du coude. On mesure la descente du poignet vers le coude, en longueurs d'avant-bras (0 vertical, 1 horizontal). La longueur de référence est la plus grande vue au repos : certains commencent l'avant-bras un peu basculé en arrière.
- **Défauts** : coude qui descend (bras à plus de 25° sous sa position de départ ; mauvais dès 54°, bons ≥ 85°), buste penché sur le côté (0,08 ; bons ≤ 0,03, mauvais jusqu'à 0,22) ou en avant.
- **Corrections** : « Basculez l'avant-bras un peu plus loin », « Gardez le coude à hauteur d'épaule », « Gardez le buste plus droit ».
- **Objectif** : 0,6 (avant-bras aux deux tiers du chemin vers l'horizontale). 0,7 compte 97 % des bons.
- **Limites** : de face, une bascule vers l'arrière ressemble à une bascule vers l'avant. Un sujet qui finit l'avant-bras très basculé en arrière est compté deux fois (1 cas sur 100).
- **Pause par la paume désactivée** pour cet exercice (`CatalogExercise.allowsHandGestures`) : la position de départ, une main levée au-dessus de l'épaule paume vers la caméra, est le geste lui-même. Le bouton pause reste.

### Extension d'épaule (m8) : écartée

- Le bras tendu part vers l'arrière, dans la profondeur. De face, il n'en reste qu'une petite montée du poignet (0,11 à 0,66 buste chez les bons, médiane 0,35).
- Essai avec cette mesure : 87 % des bons comptés à l'objectif 0,2, mais 80 à 84 % dès qu'on s'en écarte (0,15 ou 0,25), et 37 % des mauvais encore comptés. Trop fragile, sur des données Kinect plus lisses que Vision.
- Surtout, **un bras levé vers l'avant ou sur le côté donne le même signal** : l'app compterait le mauvais geste, ce qui va contre son but.
- Il faudrait une **vue de profil** (le bras recule dans le plan de l'image : l'angle bras-tronc se lit directement), donc un autre placement du téléphone pour cet exercice. En attendant, comptage manuel.

### Pour la session `graphique`

- **Pictogrammes de profil** souhaités pour la montée de genou (la cuisse vient vers la caméra) et la fente avant (les genoux se superposent de face). La fente latérale se lit bien de face.
- **Rotation de l'épaule** : les poses `guideRest` / `guideTarget` donnent le coude (`leftElbow`), mais `ArmStyle.straight` trace l'épaule directement vers le poignet. Il faudrait un style de bras qui passe par le coude pour montrer le bras en « L ».

### À tester devant la caméra

- Montée de genou : genou très haut (cuisse à l'horizontale) bien suivi par Vision, alternance des jambes.
- Fentes : grand pas en avant ou sur le côté, le patient reste-t-il dans le cadre et la silhouette de placement ? Distance minimale à revoir.
- Rotation : Vision suit-il le poignet quand l'avant-bras pointe vers la caméra (raccourci, devant le coude) ?
- Rejeu : le squat donne 70 % des bons comptés et 20 % des mauvais avec la perspective actuelle de `Tools/Replay`, loin des 85–91 % notés plus haut avec l'ancien rejeu. Ce n'est pas lié à ces ajouts, mais à vérifier.
