# Rebond – interface

À lire avant de toucher à une vue. Le contexte produit est dans `CLAUDE.md`, l'architecture dans `TECHNIQUE.md`.
Ce document applique les Human Interface Guidelines (HIG) et les ressources design partagées par l'organisateur au cas de Rebond. Chaque règle renvoie à la page HIG d'où elle vient.

## Pour qui, et quelle émotion

- **Patient type :** adulte en rééducation (genou, hanche, dos, épaule), souvent âgé, parfois peu à l'aise avec un smartphone, qui fait ses exercices seul chez lui. Il a mal, il doute, il a tendance à abandonner.
- **Émotion visée** (HIG *Design principles › Delight*) : **rassurer et encourager**. Calme, jamais culpabilisant, jamais médical. On félicite l'effort, on ne note pas le patient.
- **Le moment qui définit Rebond :** le patient fait un squat à 2 m de son téléphone, entend « Bien ! » et voit le compteur passer à 4. Tout le reste de l'app sert ce moment ou le rapport au kiné.

## Les trois questions (WWDC25 *Design foundations*)

Chaque écran doit répondre sans effort à : **Où suis-je ? Que puis-je faire ? Où puis-je aller ?**
Un titre clair (pas le logo), une action principale évidente, une suite visible.

## Deux rôles

- **Patient** (par défaut, entièrement gratuit) : les onglets ci-dessous.
- **Kiné** : Réglages › « Je suis kiné » (dernière section, pour ne pas gêner le patient) ajoute l'onglet **Kiné** (`stethoscope`), qui devient l'onglet affiché au lancement tant que l'espace est activé. Ouvrir un bilan `.rebond` l'active aussi et ouvre la fiche du patient. Le kiné garde les autres onglets pour essayer l'app côté patient. On désactive l'espace dans ses réglages (roue dentée de l'onglet Kiné) ou dans Réglages.
- **Onglet Kiné** : même style que l'accueil (cartes façon Santé). « Cette semaine » (patients suivis, à regarder, bilans reçus), « Prescrire un programme » (QR code), « Mes patients » (une carte par patient : régularité, douleur, répétitions, amplitude ; douleur forte en premier, signalée par symbole et texte), importer un bilan, offre gratuite / Rebond Pro. Fiche patient : séances à douleur forte, régularité, douleur, exercices, amplitude, programme actuel et « Ajuster le programme » (nouveau QR code). État vide avec « Importer un bilan » et « Essayer avec des patients de démo ». L'abonnement Rebond Pro y est proposé avec `SubscriptionStoreView` ; l'app patient n'affiche jamais d'écran payant.

## Structure de l'app patient

Deux onglets, plus Kiné si l'espace kiné est activé (HIG *Tab bars* : les onglets servent à naviguer, jamais à lancer une action).

| Onglet | Symbole | Contenu |
|---|---|---|
| **Accueil** | `house` | Séance du jour (les exercices de tous les programmes prévus ce jour-là, ou un jour de repos avec la prochaine séance), bouton « Commencer », puis « Suivi » : régularité de la semaine, amplitude, douleur et « Envoyer à mon kiné ». |
| **Exercices** (dès qu'un programme ou un exercice est enregistré) | `figure.mixed.cardio` | La semaine (une couleur par programme), « Mes programmes » et « Créer un programme », puis « Mes exercices » et « Créer un exercice ». |
| **Kiné** (seulement si l'espace kiné est activé) | `stethoscope` | Espace de travail du kiné, voir « Deux rôles ». Onglet affiché au lancement quand il est activé. |

### Vocabulaire : l'exercice d'abord

| Mot | Ce que c'est | Où on le crée |
|---|---|---|
| **Exercice** | Un mouvement que Rebond sait suivre : filmé (le *mouvement modèle*, l'exercice bien fait une fois) ou un exercice Rebond. C'est par lui que tout commence. « Mes exercices » contient dès le départ les exercices Rebond suivis par la caméra (une seule fois : un exercice supprimé ne revient pas de lui-même, « Sans caméra › Remettre un exercice Rebond » le rajoute). « Créer un exercice » propose donc seulement de filmer ou un exercice sans caméra (compté à la main, position tenue). | « Créer mon exercice » (Accueil vide) ou « Créer un exercice » (onglet Exercices). |
| **Programme** | Des exercices déjà créés, avec combien (séries × répétitions ou durée) et quels jours. Le patient peut en avoir plusieurs (le genou lundi, mercredi et vendredi, le dos mardi et jeudi). | À la fin de la création d'un exercice, ou d'un coup avec « Créer un programme » : composer moi-même (en piochant dans « Mes exercices »), coller le message du kiné, scanner ou photographier sa feuille. Le QR code du kiné apporte aussi un programme entier. |
| **Séance** | Ce qu'on fait un jour donné : les exercices de tous les programmes de ce jour. | Jamais : elle découle des programmes. |

- **Filmer un exercice** : filmer ou choisir une vidéo, « Analyse du mouvement… », puis un écran de vérification avant d'enregistrer (`LearnedMovementReview`). Il montre la répétition la plus nette en boucle, deux images côte à côte, « Départ » et « Arrivée » (« Position à tenir · 20 s » pour une position tenue), entre lesquelles la jauge se remplira pendant la séance, et le nombre de répétitions repérées. Quand l'analyse hésite sur le départ, une note calme « À vérifier » (icône et texte) dit comment il a été choisi. Action principale : « Enregistrer l'exercice », avec le nom. Actions secondaires : « Inverser départ et arrivée » (le mouvement est réappris, le départ devient l'arrivée), « Essayer maintenant » (une série de 5 avec la caméra pour voir la jauge monter dans le bon sens et le compte juste ; rien n'est enregistré), « Choisir une autre vidéo ».
- **Vérifier le mouvement** (page d'un exercice filmé, dans « Mes exercices » comme dans un programme) : le même écran, dans une feuille, avec « Terminé ». L'inversion y est enregistrée tout de suite, et l'écran le dit ; la refaire revient au départ d'origine.
- On crée d'abord un exercice. Une fois enregistré, l'app propose la suite : « Ajouter à « … » » pour chaque programme, « Créer un programme avec cet exercice », ou « Non, juste l'exercice ». Un exercice seul n'est dans aucune séance, mais se fait déjà avec « Essayer un exercice ».
- « Créer un exercice » ne crée jamais de programme ; « Créer un programme » crée directement un programme entier, sur l'Accueil vide comme dans l'onglet Exercices.
- **Des deux côtés** (réglage de chaque exercice d'un programme) : chaque série se fait d'un côté puis de l'autre, avec un seul film ou modèle, montré en miroir pour le second côté. Activé par défaut pour un exercice filmé d'un seul côté (une jambe, un bras). La séance affiche « Série 1 sur 3 · côté gauche », la fin de série annonce « Côté droit ». La caméra compte les deux côtés avec le même film.
- **Essayer un exercice** (hors programme) n'est pas une séance : il est enregistré pour l'historique de l'exercice, mais ne compte ni dans la régularité, ni dans le suivi, ni dans le bilan envoyé au kiné (`Session.isTrial`).

### Sans programme

L'onglet Exercices est là dès le départ, avec les exercices Rebond.

1. Carte « Pour commencer » : « Créez vos exercices, puis votre programme. » et deux étapes numérotées (filmer l'exercice bien fait, les exercices Rebond étant déjà là ; créer un programme avec ses exercices et ses jours).
   - bouton principal **« Créer mon exercice »** : filmer ou choisir une vidéo, ou un exercice sans caméra ; seule action mise en avant (HIG *Writing* : une seule suite claire sur un écran vide) ;
   - bouton secondaire **« Créer un programme »**, un menu pour un programme entier d'un coup : composer moi-même, coller le message, scanner la feuille, photo de la feuille ;
   - « Charger le programme de démo », dans les builds de développement seulement.
2. Carte « Essayer un exercice » : un exercice tout de suite, hors programme. « Choisir un exercice » les range en trois groupes : « Mes exercices filmés », « Exercices Rebond », « Sans caméra » (« Compter à la main » et « Minuteur » pour n'importe quel mouvement, puis les exercices comptés ou tenus du patient). « Composer moi-même » range « Mes exercices » dans les mêmes trois groupes, avec « Compté à la main ou minuteur » pour en ajouter un sans quitter la page.

Le QR code prescrit depuis l'espace Kiné n'a pas besoin de bouton : le patient le vise avec l'appareil photo de l'iPhone, le lien `rebond://programme` ouvre l'écran de vérification.

### Avec programme

- Onglet Exercices : « Mes programmes » et « Créer un programme » en premier (pour les gérer sans faire défiler tous les exercices), puis « Mes exercices » et « Créer un exercice » (menu : composer moi-même, coller le message, scanner la feuille, photo de la feuille, comme sur l'Accueil vide).
- Page d'un exercice : le faire maintenant, les programmes qui l'utilisent, « Ajouter à un programme », « Vérifier le mouvement » (exercice filmé), renommer, supprimer.
- Réglages (profil, rappels, avertissement médical, espace kiné, données de démo) derrière le bouton profil en haut à droite, pas dans un onglet.

## Premier lancement (HIG *Launching*, *Onboarding*, *Privacy*)

- Écran de lancement de la couleur de fond du premier écran, sans logo ni texte.
- **Un seul écran de bienvenue**, au premier lancement (`WelcomeView`) : « Votre rééducation à la maison, suivie par votre kiné. », l'avertissement médical, puis « Je suis patient » (Accueil) ou « Je suis kiné » (onglet Kiné). Aucune autorisation demandée. Le choix se change dans Réglages. Il n'apparaît pas quand l'app est ouverte par un QR code ou un bilan.
- **Pas de tutoriel** : l'Accueil sans programme montre les étapes, la séance guide le patient à la voix. L'avertissement médical est aussi en bas de l'Accueil, dans Réglages et dans le bilan PDF.
- **Aucune autorisation demandée au lancement.** La caméra est demandée au premier scan ou à la première séance, après un écran d'explication à **un seul bouton** qui ouvre l'alerte système.
- Les notifications sont proposées après la première séance réussie, quand le patient comprend leur intérêt.

## Scanner la feuille (HIG *Generative AI*, *Machine learning*)

- Capture avec le **scanner de documents de VisionKit** : recadrage et redressement automatiques, ce qui améliore la lecture. Choix d'une photo existante possible avec `PhotosPicker`.
- **Dire que c'est l'IA qui lit**, et ce qu'elle ne sait pas faire : « Apple Intelligence lit votre feuille sur l'iPhone. Vérifiez le résultat : l'écriture manuscrite peut être mal lue. »
- **Pendant la lecture** : retour rassurant et précis (« Lecture de la feuille… »), la photo reste visible en fond.
- **Écran de vérification obligatoire**, avec la photo consultable à côté :
  - les valeurs **devinées** (non trouvées sur la feuille) sont signalées « À vérifier », par une icône et du texte, jamais par la couleur seule ;
  - correction guidée (sélecteurs de séries, répétitions, durée), pas de champ libre sauf pour le nom ;
  - les exercices suivis par la caméra portent un badge « Suivi caméra » ; les autres, « Comptage manuel » ;
  - « Enregistrer » n'est actif qu'une fois le programme valide.
- **Repli** si Apple Intelligence est indisponible : un message qui dit pourquoi et ce qu'on peut faire, avec un bouton direct vers Réglages quand c'est utile, puis la saisie manuelle.

## La séance (HIG *Workouts*, *Feedback*, *Machine learning › Calibration*)

Le téléphone est posé à 2–3 m. **Tout doit se lire de loin et s'entendre sans regarder.**

1. **Placement.** Écran d'aide : poser le téléphone à hauteur de hanche, de face, corps entier visible. Une silhouette indique où se tenir ; elle passe de « proche » à « aligné » avec un symbole et une consigne vocale, pas seulement une couleur.
2. **Calibrage** (mesure de la position debout). Expliquer pourquoi (« Restez immobile, je mesure votre position de départ »), confirmer la réussite, permettre d'annuler. Une seule fois par série.
3. **Démonstration.** Le pictogramme montre le mouvement une fois. Bouton « Passer » (HIG *Agency* : un parcours guidé doit pouvoir être passé).
4. **Série.** Affichage distinctif d'une séance active :
   - compteur géant (`.system(size:)` arrondi, ≥ 96 pt), « 4 / 10 » ;
   - jauge de profondeur ;
   - correction en cours : texte court + symbole + voix ;
   - **Pause** et **Terminer** toujours visibles, en bas, ≥ 60 pt de haut (atteignables à la main en revenant au téléphone).
5. **Fin de série.** Résumé (répétitions complètes, incomplètes, meilleure amplitude), puis « Série suivante » ou « Terminer la séance ».
6. **Fin de séance.** Douleur 0–10, puis résumé. Une séance terminée en quelques secondes sans aucune répétition est proposée à l'abandon plutôt qu'enregistrée d'office.

Règles pendant la série :
- **Retours multimodaux** : voix + texte + symbole. La couleur ne porte jamais seule l'information.
- **Ne pas surcharger** : une seule correction à la fois, la plus importante ; « Plus lentement » au plus une fois toutes les 3 répétitions.
- **Confiance** : quand Vision voit mal le corps, on n'affiche ni compteur qui bouge ni correction ; on dit « Je ne vous vois plus en entier » et on montre la silhouette.
- **Commandes à distance** : des signes de la main, sans revenir au téléphone (tableau ci-dessous). Chacun est toujours doublé par un bouton à l'écran.
- **Aucune commande physique détournée** : pas de boutons de volume, pas de commandes AirPods (HIG *Playing audio* : ne pas détourner les contrôles audio ; App Review 2.5.9).
- **Astuces (TipKit)** : les commandes mains libres se découvrent au bon moment, une astuce à la fois, jamais pendant le placement ou le calibrage (voir « Astuces »).
- **Haptique** : inutile sur l'iPhone pendant la série (téléphone posé) ; c'est la montre qui tapote (voir « Apple Watch »). Sur l'iPhone, seulement dans l'interface tenue en main (sélecteur de douleur, enregistrement réussi), avec les retours système.

### Signes de la main (HIG *Gestures*, *Feedback*)

Le patient est à 2–3 m : chaque commande de la séance a son signe, distinct des autres et des mouvements des exercices. Tous passent par `SessionRemote`, comme les boutons, Siri et la montre : un même signe fait la même chose partout, et seulement ce qui a du sens à ce moment.

| Signe | Comment le faire | Ce qu'il fait | Où |
|---|---|---|---|
| Paume ouverte (`hand.raised.fill`) | Une main levée à hauteur d'épaule, paume vers le téléphone, l'autre main plus basse, tenue ~0,9 s | Pause ; avant un maintien, lance le minuteur | Série caméra (placement, démonstration, série), maintien, repos |
| Paume ouverte, en pause | N'importe quelle main ouverte du patient, à n'importe quelle hauteur, même tout près du téléphone, ~0,4 s | Reprendre | Toute pause |
| Pouce levé (`hand.thumbsup.fill`) | Poing fermé, pouce vers le haut, main au-dessus du milieu du buste (devant la poitrine suffit), une main ou les deux, ~0,6 s | « Suivant » : série suivante, fin du repos, « Je suis prêt » après le film ; confirme la fin de séance | Partout, en pause aussi (la série se termine avec ce qui a été fait) |
| V, deux doigts (`hand.point.up.fill`) | Index et majeur tendus, annulaire et auriculaire repliés, main au-dessus du milieu du buste, ~0,8 s | Exercice suivant (s'il n'y en a plus : terminer la séance, demandé à nouveau) | Partout, en pause aussi |
| Bras croisés (`xmark`) | Les deux avant-bras croisés devant la poitrine, ~1,2 s, sans bouger | Terminer la séance : « Terminer la séance ? Pouce levé pour confirmer » (8 s) | Partout |
| Pincer / écarter | Pouce et index qui se rejoignent ou s'écartent, main levée | Le modèle en grand, ou de retour dans sa carte | Série caméra |

Règles :
- **Éviter les déclenchements accidentels** : un signe compte seulement tenu immobile (le poignet bouge de moins de 0,15 longueur de buste), le corps immobile ; une main qui traverse la forme pendant un exercice ne compte pas. Mains jointes devant la poitrine (squat) : aucun signe. Après un signe, ou une pause et une reprise (quelle qu'en soit l'origine), la main doit redescendre avant qu'un autre compte.
- **Confirmer de loin** : chaque signe reconnu est confirmé à l'écran (symbole et texte, `SessionAction.confirmation`) et à la voix ; un signe sans effet à ce moment ne fait rien.
- **Montrer qu'ils existent** : chaque écran de la séance affiche une petite légende des signes qui y marchent (symbole + texte court : « Pause · Série suivante »), le signe reconnu s'y allume un instant.
- **Écrans sans caméra de séance** (film de l'exercice filmé, maintien) : la caméra frontale tourne sans aperçu pour voir les signes (`GestureCamera`), seulement si l'accès à la caméra est déjà accordé ; ces écrans ne le demandent jamais. Sans accès, ni légende ni signe : les boutons restent.

| Écran | Signes de la légende |
|---|---|
| Film de l'exercice | Pouce : « Je suis prêt » · Bras croisés : terminer |
| Maintien, avant le minuteur | Paume : « Commencer » |
| Maintien en cours | Paume : « Pause » · Pouce : « Série suivante » |
| Maintien en pause | Paume : « Reprendre » · Pouce : « Série suivante » · V : exercice suivant · Bras croisés : terminer |
| Maintien terminé | Pouce : « Continuer » · Bras croisés : terminer |

### Voix du coach (HIG *Playing audio*, *Writing*)

- Session audio `.playback` / `.voicePrompt`, avec atténuation de la musique pendant que le coach parle (`duckOthers`). Rendre la main aux autres apps en fin de séance.
- Bouton « Couper la voix » visible ; le texte reste affiché.
- Phrases de 2 à 5 mots, à l'impératif, vouvoiement : « Descendez encore un peu », « Gardez le buste droit », « Bien ! ».

## Douleur et sécurité

- Sélecteur 0–10 avec repères en mots (0 « Aucune », 5 « Modérée », 10 « Insupportable ») et haptique de sélection.
- À partir de 7 : message calme, non bloquant, sous le sélecteur : « Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné. » Pas d'alerte modale (HIG *Feedback* : les alertes sont pour l'information critique et actionnable).

## Progrès et rapport (HIG *Charting data*)

- **Swift Charts**, types courants seulement : barres pour la régularité (séances par semaine), ligne pour l'amplitude et la douleur.
- Chaque graphique a un titre qui dit ce qu'il montre (« Votre amplitude au squat progresse »), des unités explicites et une description pour VoiceOver.
- L'amplitude est exprimée en **% de l'objectif fixé** ; une phrase l'explique dans l'app et dans le PDF.
- Le PDF reprend les mêmes graphiques (rendus avec `ImageRenderer`), la période en dates exactes, les séances à douleur ≥ 7 signalées, et l'avertissement médical.
- « Envoyer à mon kiné » ouvre la feuille de partage (`ShareLink`). Rien ne part sans ce geste.

## Visuel

- **Liquid Glass** (HIG *Materials*) : uniquement pour la couche des contrôles et de la navigation (barres, boutons flottants), jamais dans le contenu. Sur l'image caméra, boutons en verre « clair » avec un voile sombre derrière pour garder le contraste. Les composants système l'apportent d'eux-mêmes : ne pas réinventer de barres.
- **Typographie** : styles de texte système uniquement, Dynamic Type jusqu'aux tailles d'accessibilité. Seul le compteur de séance a une taille fixe (et reste lisible à 2 m).
- **Couleurs** : couleurs sémantiques système ; **une seule couleur d'accent** (boutons, sélection). Vert, orange et rouge réservés aux états de la séance, toujours doublés d'un symbole. Mode sombre et Contraste augmenté vérifiés.
- **Symboles** : SF Symbols partout (familles `figure.*` pour les exercices), symboles animés pour les confirmations. Pas d'icônes maison.
- **Pictogramme du mouvement** : dessiné en `Canvas`, sans genre (HIG *Inclusion*), immobile si « Réduire les animations » est activé. Un mouvement fait vers la caméra (genou ou jambe levés devant, fente avant, assis-debout) est montré de profil ; la rotation de l'épaule plie le bras au coude (en L) ; un exercice d'un côté ne bouge que ce côté. Le contour de placement (`GuideFigure`) reste un corps quelle que soit la pose reçue : articulations manquantes reconstituées, buste de largeur normale, membres de longueur plausible ; il se pose sur les pieds du patient sans trembler (`GuideAnchor`). Les articulations suivies grossissent un instant à chaque palier d'amplitude atteint, pour voir l'objectif de loin.
- **Icône de l'app** : réalisée avec Icon Composer (couches, rendu Liquid Glass, variantes sombre et teintée), à partir des gabarits Apple Design Resources.

## Accessibilité (HIG *Accessibility*)

- Cibles tactiles ≥ 44 × 44 pt ; contraste ≥ 4,5:1 pour le texte courant.
- VoiceOver : chaque contrôle a un libellé ; le compteur annonce les répétitions ; les graphiques ont un résumé.
- Toute action par geste a une alternative par bouton.
- Pas d'élément limité dans le temps sans possibilité de prolonger (le calibrage attend le patient).
- Tester une fois avec VoiceOver, une fois en très grande taille de texte, une fois en mode sombre.

## Rédaction (HIG *Writing*, *Inclusion*)

- Vouvoiement partout, ton calme et encourageant, langage simple : pas de jargon médical (« amplitude » est expliqué), pas d'humour sur la douleur.
- Boutons formulés comme des actions : « Commencer la séance », « Envoyer à mon kiné ».
- Messages d'erreur : ce qui s'est passé, puis ce qu'on peut faire.
- Majuscule uniquement en début de libellé.

## Apple Watch (HIG *Designing for watchOS*, *Workouts*, *Playing haptics*, *Complications*)

La montre sert le moment de l'exercice : le patient ne revient pas au téléphone posé à 2 m. Elle **ne compte rien** : l'iPhone et sa caméra restent la seule source, la montre affiche et transmet.

- **Ouverture automatique** : au lancement d'une séance sur l'iPhone, l'app de la montre s'ouvre seule (`startWatchApp`) et démarre un entraînement. Aucune manipulation.
- **Hors séance** : « Séance du jour » (nombre d'exercices, durée), jauge de la semaine, « Lancez la séance sur votre iPhone : votre montre suivra vos séries ».
- **Pendant la série** : nom de l'exercice, compteur dans un anneau (« 4 sur 10 », ou « 12 sur 30 s » pour un maintien), « Série 2 sur 3 », fréquence cardiaque en haut à droite. En bas, **Pause / Reprendre** (« Commencer » avant le départ d'un maintien) et **Série suivante**. Pas de bouton pause pour le comptage manuel.
- **Double Tap** (pincer deux fois) appuie sur le bouton principal : pause, ou série suivante quand la série est terminée ou n'a pas de pause. L'astuce « Pincez deux fois pour mettre en pause » l'apprend (voir « Astuces »).
- **Haptique**, une seule à la fois, la plus importante : un tapotement à chaque répétition (toutes les 10 s pour un maintien), « succès » à l'objectif atteint, « stop » à la pause, « départ » à la reprise, une notification à chaque nouvelle série.
- **Placement, douleur** : « Placez-vous devant l'iPhone », puis « Séries terminées ! Indiquez votre douleur sur l'iPhone ».
- **Fin** : « Séance terminée, bravo ! », durée, cœur moyen, calories si mesurées, « Enregistrée dans Santé ». Une séance abandonnée sur l'iPhone n'est pas enregistrée.
- **Complications** : anneau de régularité (circulaire, coin) et séance du jour (rectangulaire, en ligne), remontée dans la Smart Stack tant que la séance du jour reste à faire.

## Intégration système (HIG *Widgets*, *Live Activities*, *Siri*, *Managing notifications*, *HealthKit*)

- **Rappels** : notification locale les jours de séance (niveau « actif », jamais « urgent ») et rappel hebdomadaire d'envoi du rapport. Réglables dans l'app.
- **App Intents** : « Démarrer ma séance Rebond » dans Raccourcis, Spotlight et le centre de contrôle ; « Combien de séances cette semaine » (iPhone et montre) ; pendant la séance, « Pause dans Rebond », « Série suivante dans Rebond » (iPhone et montre), « Passer à l'exercice suivant dans Rebond » et « Terminer la séance dans Rebond » (iPhone), à la voix, les mains occupées. Siri répond selon l'état réel de la séance : « Pause », « Série suivante », « Exercice suivant », « Séance terminée », ou pourquoi rien ne se passe (« Aucune séance en cours », « Indiquez votre douleur sur l'iPhone »). Avant de terminer, Siri demande « Terminer la séance ? » ; la séance passe ensuite à la douleur, rien n'est perdu. Boutons, signes de la main, Siri, montre et Live Activity déclenchent exactement les mêmes actions.
- **Live Activity** de la série (écran verrouillé, Dynamic Island, Smart Stack de la montre) avec les boutons **Pause** et **Série suivante**, utilisables sans déverrouiller.
- **Widgets** « Séance du jour » et « Régularité » : le toucher mène là où le widget le dit. Séance du jour à faire → la séance ; jour de repos (« Prochaine séance demain ») ou séance faite → Accueil ; sans programme (« Aucun programme · Touchez pour créer le vôtre. », bouton « Créer un programme » en taille moyenne) → « Créer un programme » sur Accueil. Le bouton « Commencer » du widget moyen n'apparaît que si la séance du jour reste à faire.
- **Santé** : l'offre « Ajouter vos séances à l'app Santé ? » apparaît une fois en fin de séance (après celle des rappels, jamais les deux en même temps), et un interrupteur « Enregistrer dans Santé » est dans Réglages. Le résumé indique « Enregistrée dans Santé » ou « … par votre Apple Watch ». L'autorisation n'est jamais demandée au lancement.
- Siri AI n'est pas disponible dans l'UE avec iOS 27 : les phrases sont de simples App Shortcuts, aussi proposés dans Spotlight et Raccourcis ; aucune fonctionnalité ne repose sur Siri AI.

## Astuces (HIG *Offering help*, TipKit)

Trois astuces seulement, pour les commandes qu'on ne devine pas. Chacune a son écran et son moment : **jamais plus d'une à la fois**, jamais pendant le placement ou le calibrage, jamais par-dessus une offre (rappels, Santé). Titre court, message d'une phrase, vouvoiement ; la croix les ferme pour de bon.

| Astuce | Où, quand | Texte |
|---|---|---|
| Siri | Série en cours (caméra ou maintien), quand le patient revient au téléphone mettre en pause avec le bouton, à partir de sa deuxième séance, sans montre qui suit la séance. Une fois. | « Mettez en pause à la voix » · « Dites « Dis Siri, pause dans Rebond » pour mettre en pause sans revenir au téléphone. » |
| Apple Watch | Résumé de fin de séance, si une montre est jumelée sans l'app Rebond et qu'aucune offre n'est affichée. Deux fois au plus ; disparaît dès que l'app est installée. | « Suivez vos séries sur votre Apple Watch » · « Installez Rebond sur votre montre depuis l'app Watch : la série s'affiche à votre poignet, qui tapote à chaque répétition. » |
| Double Tap (montre) | Écran de la série, dès que l'iPhone compte (2 répétitions ou 2 secondes), tant que la série peut être mise en pause. Remplace la ligne « Série 1 sur 3 ». Une fois. | « Pincez deux fois pour mettre en pause » (titre seul : la série doit rester lisible) |

Une pause demandée par Siri ou la Live Activity retire l'astuce Siri : le patient a trouvé.

## Traduction

String Catalog, français (langue source) et anglais. Les phrases du coach passent aussi par le catalogue. Pas de texte dans les images.
