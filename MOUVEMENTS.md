# Ajouter un mouvement suivi par la caméra

Guide pour la session Claude chargée du **moteur** (branche `technique`). L'interface est gérée par une autre session sur la branche `graphique` : voir « Qui fait quoi » à la fin.

Lire d'abord `CLAUDE.md` (règles du projet), `TECHNIQUE.md` (architecture) et `JOURNAL.md` (ce qui a déjà été essayé et pourquoi).

## Ce qui existe

| Exercice | `id` | Compteur | Mesure | Objectif |
|---|---|---|---|---|
| Squat | `squat` | `RepCounter` | descente des hanches, en longueurs de buste | 0,6 |
| Élévation latérale des bras | `lateral-raise` | `ArmRaiseCounter` (deux bras) | angle bras-tronc | 80° |
| Élévation latérale d'un bras | `shoulder-abduction` | `ArmRaiseCounter(arms: .either)` | angle bras-tronc | 110° |
| Élévation des bras en diagonale | `scaption` | `ArmRaiseCounter(arms: .either)` | angle bras-tronc | 90° |
| Assis-debout | `sit-to-stand` | `SitToStandCounter` | montée des hanches au-dessus de l'assise | 0,6 |
| Élévation de la jambe tendue | `leg-raise` | `LegRaiseCounter` | montée du genou vers la hanche | 0,3 |
| Montée de genou (enjambement) | `hurdle-step` | `LegRaiseCounter(style: .bentKnee)` | montée du genou vers la hanche, genou plié | 0,45 |
| Fente avant | `forward-lunge` | `LungeCounter(direction: .forward)` | descente des hanches, en longueurs de buste | 0,45 |
| Fente latérale | `side-lunge` | `LungeCounter(direction: .side)` | décalage des hanches sur le côté, en longueurs de buste | 0,4 |
| Rotation de l'épaule (90/90) | `shoulder-rotation` | `ShoulderRotationCounter` | descente du poignet vers le coude, en longueurs d'avant-bras | 0,6 |

Une répétition **compte dès 70 % de l'objectif** (palier « Bien », `AmplitudeTier.goodThreshold`) ; l'objectif reste le 100 % et l'amplitude peut le dépasser (0,7 à 1,2 et plus).

Résultats sur UI-PRMD, téléphone à 2,5 m (bons comptés / mauvais encore comptés) :

| Exercice | Bons | Mauvais |
|---|---|---|
| Squat | 90 % | 41 % |
| Montée de genou | 99 % | 59 % |
| Fente avant | 99 % | 58 % |
| Fente latérale | 100 % | 46 % |
| Assis-debout | 100 % | 51 % |
| Jambe tendue | 100 % (1 double) | 72 % |
| Un bras | 99 % | 60 % |
| Rotation de l'épaule | 100 % (1 double) | 49 % |
| Diagonale | 100 % | 55 % |

Les mauvais mouvements d'UI-PRMD sont souvent trop courts : depuis le seuil à 70 %, ceux qui atteignent 70 % sont comptés (palier « Bien »), c'est voulu. Les défauts de posture les refusent toujours.

L'extension d'épaule (n° 8) n'est **pas** suivie par la caméra : de face, le bras qui recule ne se distingue pas d'un bras levé devant ou sur le côté (détails dans `JOURNAL.md`). Elle reste en comptage manuel.

## Les fichiers à toucher

| Fichier | Quoi |
|---|---|
| `Rebond/Motion/<Nom>Counter.swift` | le compteur (nouveau fichier) |
| `Rebond/Motion/RepCounter.swift` | `enum Correction` : nouvelles corrections et leur message |
| `Rebond/Views/Session/SkeletonOverlay.swift` | `Correction.bodyJoints` : les articulations à colorer en rouge (le `switch` doit rester exhaustif) |
| `Rebond/Motion/PoseAnalyzer.swift` | `PoseMeasure` : seulement s'il faut une articulation de plus |
| `Rebond/Catalog/CatalogExercise.swift` | un cas d'`Analysis`, `makeCounter()`, l'entrée du catalogue, `all` |
| `Rebond/SheetReader/SheetReader.swift` | `ExerciseKind` : nouveau cas, son `catalogID` et la description `@Guide` en français |
| `RebondTests/` | les tests du compteur |
| `Tools/Replay/` | le rejeu des données Kinect (`build.sh`, `main.swift`) |
| `JOURNAL.md` | une section avec les résultats |

Ne pas toucher aux autres vues : elles appartiennent à la branche `graphique`.

## Étape 1 · Choisir le mouvement

- Utile en rééducation, faisable seul chez soi, sans matériel (une chaise au plus).
- **Lisible en 2D de face** : le téléphone est posé à hauteur de hanche, à 2–3 m, face au patient. Vision ne donne pas la profondeur. Un mouvement qui va vers la caméra (jambe tendue devant soi) se voit mal : il faut mesurer autre chose (cf. la jambe, mesurée au genou).
- Debout de préférence : un mouvement au sol (gainage, pont) se cadre mal et reste en comptage manuel ou au minuteur.

## Étape 2 · Les données

**UI-PRMD** (University of Idaho) : 10 personnes × 10 répétitions, en version correcte et incorrecte, capturées par Kinect.

| N° | Mouvement | N° | Mouvement |
|---|---|---|---|
| 1 | squat profond (fait) | 6 | élévation de la jambe tendue (fait) |
| 2 | enjambement de haie (fait) | 7 | abduction d'épaule (fait) |
| 3 | fente avant (fait) | 8 | extension d'épaule (écartée : illisible de face) |
| 4 | fente latérale (fait) | 9 | rotation interne/externe d'épaule (fait, en 90/90) |
| 5 | assis-debout (fait) | 10 | scaption (fait) |

```bash
sh Tools/Replay/download.sh ~/uiprmd 4
```

Les fichiers vont dans `~/uiprmd/correct/…` et `~/uiprmd/incorrect/…`. Ce sont des données : ne pas les mettre dans le dépôt.

**Pièges déjà rencontrés :**
- Les positions sont relatives au parent, avec des angles d'Euler. La conversion est dans `Tools/Replay/kinect.swift`. **L'ordre d'Euler est Z·X·Y** (convention BVH) : l'ordre z·y·x du script Python d'origine fait basculer une jambe levée vers le haut vers 90°.
- Les chevilles et les pieds Kinect sont peu fiables : ne pas régler un seuil dessus.
- Certains segments ne commencent pas à la position de départ de l'app (l'assis-debout part debout) : `main.swift` les fait tourner pour démarrer au bon moment.
- Le rejeu projette en **perspective**, depuis un téléphone à hauteur de hanche à 2,5 m (`PERSP=250`). C'est ce qui a montré que la cheville monte à peine de face sous 50° de jambe levée. Vérifier aussi à 200 et 300.

## Étape 3 · Observer avant de coder

```bash
sh Tools/Replay/build.sh
DIAG=1 ./Tools/Replay/replay ~/uiprmd/correct c <n°> <objectif>
DIAG=1 ./Tools/Replay/replay ~/uiprmd/incorrect i <n°> <objectif>
DEBUG=s03e05 ./Tools/Replay/replay ~/uiprmd/correct c <n°> <objectif>
```

`DIAG` affiche les déciles des mesures (descente, montée, inclinaison du buste…) pour les bons et les mauvais mouvements : on y lit où placer l'objectif et les seuils de défaut. `DEBUG` trace une répétition image par image. Ajouter le cas du nouveau mouvement dans `makeCounter()` de `main.swift` (et ses diagnostics si besoin).

## Étape 4 · Le compteur

- Un `nonisolated struct` conforme à `MovementCounter` : `mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate`.
- **Réutiliser `RepCycle`** (`Motion/RepCycle.swift`) : repos → aller → 70 % de l'objectif (`counted`) → retour, répétitions incomplètes sous 70 %, défaut confirmé sur 3 images, « trop rapide ». Le compteur ne fait que calculer **une valeur** (0 au repos, l'objectif à atteindre) et dire quel défaut il voit. Modèle : `SitToStandCounter` ou `LegRaiseCounter`.
- **Calibrage** : mesurer la position de départ quand le patient est immobile (environ 8 images, 0,5 s), puis émettre `.calibrated`. Tout se mesure ensuite par rapport à elle.
- **Normaliser** les distances par la longueur du buste mesurée au repos (`torsoLength`) : l'échelle à l'écran dépend de la distance au téléphone.
- **Lisser** la valeur (médiane sur 3 images) : Vision se trompe parfois sur une image.
- **Image miroir** : x est inversé (le patient se voit comme dans un miroir). Accepter le bras ou la jambe gauche comme droite quand c'est un exercice d'un seul côté.
- **Corps perdu** : sans mesure pendant plus de 1,5 s, abandonner la répétition (`abandon()`).
- **Objectifs adaptés à la rééducation** : patients souvent âgés, amplitudes partielles (le squat vise 0,6 buste, pas un squat profond).
- **Corrections** : une ou deux, les plus utiles. Message court à l'impératif, vouvoiement (« Gardez la jambe tendue »). Ce sont des conseils, jamais des consignes médicales.
- `progress` : 0 au repos, 1 à l'objectif (la jauge à l'écran le suit). `RepResult.amplitude` : fraction de l'objectif (1 = atteint), comptée dès 0,7. Le seuil de bruit (`noise`) se met à la moitié de l'objectif : entre 50 et 70 %, le patient entend la correction « plus loin ».

## Étape 5 · Le catalogue et la lecture de la feuille

Dans `CatalogExercise.swift` :
- un cas d'`Analysis` avec son objectif, et la ligne dans `makeCounter()` ;
- l'entrée : `id` stable en kebab-case, `name` en français, `symbol` (SF Symbol de repli), `highlightedJoints`, `returnCue` (dit dès 70 % de l'objectif : « Redescendez doucement »), `amplitudeMeaning` (« Hauteur de la jambe, en % de la hauteur visée ») ;
- `guideRest` et `guideTarget` : les poses du pictogramme animé, vu de face, en miroir, dans une boîte unité (origine en haut à gauche) ;
- `armStyle` et `fillsGaugeUpward` ;
- l'ajouter à `all`.

Dans `SheetReader.swift`, ajouter le cas à `ExerciseKind`, son `catalogID`, et compléter la description `@Guide` : c'est elle qui permet au modèle embarqué de reconnaître l'exercice sur la feuille du kiné.

## Étape 6 · Régler sur les données

```bash
./Tools/Replay/replay ~/uiprmd/correct c <n°> <objectif>
./Tools/Replay/replay ~/uiprmd/incorrect i <n°> <objectif>
```

- **Viser ≥ 85 % des bons mouvements comptés.** Un patient qui fait bien et n'est pas compté se décourage : c'est le pire cas.
- **Puis réduire les mauvais comptés** avec les défauts, sans faire baisser les bons.
- Tester à `PERSP=200`, `250` et `300`.
- Noter les chiffres finaux : ils vont dans le journal et dans ce guide.

## Étape 7 · Les tests

Dans `RebondTests/` (Swift Testing), sur des corps synthétiques, comme `MotionTests.swift` et `RehabExerciseTests.swift` (`Feeder` envoie les mesures à 15 images par seconde) :
- le calibrage se fait (et ne se fait pas dans une mauvaise position de départ) ;
- une répétition complète est comptée, avec la bonne amplitude ;
- une répétition partielle est incomplète, avec la correction attendue ;
- le défaut principal est rejeté ;
- l'identifiant est bien relié au catalogue et à `ExerciseKind`.

```bash
xcodebuild test -scheme Rebond -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Tous les tests existants doivent rester verts, sans nouvel avertissement.

## Étape 8 · Devant la caméra

Le simulateur n'a pas de caméra : tester sur un iPhone, posé à hauteur de hanche à 2–3 m.
- Dix bonnes répétitions : toutes comptées ?
- Les défauts principaux : signalés, avec la bonne consigne ?
- La pause par la paume ouverte ne doit pas se déclencher pendant l'exercice (attention aux exercices d'un bras : une main levée à hauteur d'épaule ressemble au geste).
- Lumière faible, vêtements amples, une autre personne dans la pièce.

## Étape 9 · Terminer

- Section dans `JOURNAL.md` : mesure, objectif, seuils, résultats UI-PRMD, limites, ce qui reste à tester.
- Mettre à jour le tableau « Ce qui existe » en haut de ce guide.
- Demander à la session `graphique` le pictogramme du nouvel exercice (voir ci-dessous).
- Commit sur `technique` (messages en français, `feat: …`), puis push.

## Qui fait quoi

| Branche | Session | Périmètre |
|---|---|---|
| `technique` | moteur | `Motion/`, `Catalog/`, `SheetReader/`, `Correction.bodyJoints`, `RebondTests/`, `Tools/` |
| `graphique` | interface | `Views/`, `App/`, `Assets`, l'icône, les pictogrammes (`ExerciseIcon`, `MovementGuide`) |

- Le pictogramme de la liste (`ExerciseIcon`) est dessiné côté `graphique`. Le moteur fournit les poses `guideRest` / `guideTarget` ; si l'exercice se lit mal de face, le signaler dans le journal pour que l'interface le dessine de profil.
- `SkeletonOverlay.swift` est dans `Views/` mais `Correction.bodyJoints` reste au moteur : ne modifier que cette extension.
- Récupérer régulièrement le travail de l'autre branche (`git merge origin/graphique`, ou via `main`) pour limiter les conflits.
