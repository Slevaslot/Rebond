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
| **Exercices** (dès qu'un programme ou un exercice est enregistré) | `figure.mixed.cardio` | La semaine (une couleur par programme), « Ajouter un exercice », « Mes programmes » et « Créer un programme », « Mes exercices ». |
| **Kiné** (seulement si l'espace kiné est activé) | `stethoscope` | Espace de travail du kiné, voir « Deux rôles ». Onglet affiché au lancement quand il est activé. |

**Vocabulaire côté patient :** un *programme* regroupe des exercices sur des jours de la semaine (le patient peut en avoir plusieurs : le genou lundi, mercredi et vendredi, le dos mardi et jeudi). La *séance* est ce qu'on fait un jour donné : les exercices de tous les programmes de ce jour. *Mes exercices* rassemble les exercices connus du patient (filmés chez le kiné, exercices Rebond, lus sur une feuille).

### Sans programme

La fonctionnalité principale : **filmer les exercices chez le kiné**. Rebond apprend chaque mouvement sur la vidéo, puis le suit à la caméra à la maison. C'est la seule action mise en avant (HIG *Writing* : une seule suite claire sur un écran vide). Pas d'onglet Exercices tant que rien n'est enregistré : l'Accueil suffit.

1. Carte « Votre programme » : « Filmez vos exercices chez votre kiné. » et une phrase qui dit ce que Rebond en fait.
   - bouton principal **« Filmer chez le kiné »** ;
   - bouton secondaire « Autres façons », un menu : vidéos déjà filmées, scanner ou photographier la feuille, coller le message, composer moi-même ;
   - « Créer un programme avec mes exercices » si des exercices ont déjà été ajoutés seuls ;
   - « Charger le programme de démo », dans les builds de développement seulement.
2. Carte « Faire un exercice » : essayer tout de suite un exercice suivi par la caméra, sans programme.

Le QR code prescrit depuis l'espace Kiné n'a pas besoin de bouton : le patient le vise avec l'appareil photo de l'iPhone, le lien `rebond://programme` ouvre l'écran de vérification.

### Avec programme

- « Ajouter un exercice » (onglet Exercices) : filmer ou choisir une vidéo, exercice Rebond, et en raccourci la feuille ou le message du kiné (qui font un programme entier).
- Réglages (profil, rappels, avertissement médical, espace kiné, données de démo) derrière le bouton profil en haut à droite, pas dans un onglet.

## Premier lancement (HIG *Launching*, *Onboarding*, *Privacy*)

- Écran de lancement de la couleur de fond du premier écran, sans logo ni texte.
- **Pas d'écran d'accueil ni de tutoriel** (décision dans `CLAUDE.md`) : l'app s'ouvre sur l'Accueil sans programme décrit plus haut, et la séance guide le patient à la voix. L'avertissement « Rebond ne remplace pas l'avis d'un professionnel de santé » est dans Réglages et dans le bilan PDF.
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
- **Pause à distance** : paume ouverte levée environ 0,6 s. Toujours doublée par le bouton à l'écran.
- **Aucune commande physique détournée** : pas de boutons de volume, pas de commandes AirPods (HIG *Playing audio* : ne pas détourner les contrôles audio ; App Review 2.5.9).
- **Haptique** : inutile pendant la série (téléphone posé). Utilisée seulement dans l'interface tenue en main (sélecteur de douleur, enregistrement réussi), avec les retours système.

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
- **Pictogramme du mouvement** : dessiné en `Canvas`, sans genre (HIG *Inclusion*), immobile si « Réduire les animations » est activé.
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

## Intégration système (bonus, HIG *Widgets*, *Siri*, *Managing notifications*)

- **Rappels** : notification locale les jours de séance (niveau « actif », jamais « urgent ») et rappel hebdomadaire d'envoi du rapport. Réglables dans l'app.
- **App Intents** : « Démarrer ma séance Rebond » dans Raccourcis, Spotlight et le centre de contrôle.
- **Widget** « Prochaine séance » (petit et rectangulaire pour l'écran verrouillé), qui ouvre directement la séance.
- Siri AI n'est pas disponible dans l'UE avec iOS 27 : les App Intents restent utilisables via Raccourcis et Spotlight, mais aucune fonctionnalité ne repose sur Siri.

## Traduction

String Catalog, français (langue source) et anglais. Les phrases du coach passent aussi par le catalogue. Pas de texte dans les images.
