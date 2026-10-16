# Rebond – modèle économique et lancement

Livrable demandé par le Build Challenge (« a go-to-market plan, including monetization »). À compléter par l'équipe avec les retours recueillis pendant les deux jours.

## Le problème

- La rééducation se joue à la maison : le kiné voit son patient 1 à 3 fois par semaine, le patient fait ses exercices seul les autres jours.
- Le kiné ne sait pas si un traitement échoue parce qu'il est inefficace ou parce que le patient a sauté ou mal fait ses exercices.
- Aujourd'hui : une feuille photocopiée et aucun retour entre deux séances.

> À sourcer avant le pitch : taux d'observance des exercices à domicile, nombre de kinés libéraux en France (CNOMK) et de patients suivis.

## Le client, c'est le kiné

**Le patient ne paie jamais.** Il souffre, il est souvent âgé, il suit une rééducation de quelques semaines : lui faire payer freine l'adoption et pose une question éthique. L'app patient est entièrement gratuite.

**Le kiné paie, parce que c'est lui qui gagne** : il voit enfin ce qui se passe entre deux séances, ajuste son traitement, justifie ses décisions et fidélise ses patients.

| Pour le kiné (Rebond Pro, payant) | Pour le patient (gratuit) |
|---|---|
| Prescrire un programme en un QR code, sans feuille à recopier | Le programme arrive en un geste (QR code ou scan de la feuille) |
| Suivre chaque patient : régularité, répétitions, amplitude, douleur | Un coach à la voix qui compte et conseille |
| Être alerté des séances douloureuses | Ses progrès visibles, semaine après semaine |
| Aucun serveur, aucune donnée hébergée : simple à adopter | Tout reste sur son iPhone ; il choisit quand envoyer son bilan |

## Des offres selon le volume de patients

| | Gratuite | Rebond Pro 10 | Rebond Pro 30 | Rebond Cabinet |
|---|---|---|---|---|
| Patients suivis | **3** | **10** | **30** | **Illimité** |
| Mensuel (TTC) | 0 € | 9,99 € | 19,99 € | 39,99 € |
| Annuel (TTC, 2 mois offerts) | 0 € | 99,99 € | 199,99 € | 399,99 € |
| Essai | – | 1 mois offert | 1 mois offert | 1 mois offert |

Toutes les fonctions sont dans toutes les offres (prescription par QR code, suivi, alertes, programme renvoyé) ; seul le nombre de patients suivis change. Données sur l'iPhone, aucun serveur.

Les trois offres sont des niveaux d'un même groupe d'abonnements App Store : le kiné passe à l'offre supérieure en un geste, au prorata, et l'écran d'abonnement lui conseille l'offre qui correspond à son nombre de patients.

Le patient ne paie jamais.

**Pourquoi ce découpage :**
- L'offre gratuite fait adopter l'outil : le kiné l'essaie sur 3 patients, avec toutes les fonctions locales.
- Le moment de payer est naturel : au 4ᵉ patient, il a déjà vu la valeur ; puis le prix suit son activité (10, 30, illimité).
- Pas de serveur : rien à héberger, aucune donnée de santé confiée à un tiers, adoption simple pour le cabinet.

**État pour le hackathon :**
- Le build App Store contient l'offre gratuite et les trois offres Rebond Pro (StoreKit 2). L'écran d'achat ne promet que ce qui existe déjà.
- L'espace kiné est un onglet de la même app, activé dans Réglages (« Je suis kiné ») ou en ouvrant un bilan. Des patients de démo permettent de le montrer sans attendre de vrais bilans.
- La version connectée de démo (serveur) a été abandonnée : tout reste local. Une version hébergée (HDS, consentement du patient, vérification RPPS) reste une piste après le hackathon, pas une promesse de l'offre.

## Hypothèses à tester pendant le hackathon (équipe business)

1. **Les kinés paieraient-ils 20 € par mois ?** Appeler 5 kinés : combien de patients ont-ils en rééducation à domicile ? Liraient-ils un bilan hebdomadaire ?
2. **Le QR code remplace-t-il vraiment la feuille ?** Est-ce plus rapide pour eux que d'écrire la feuille à la main ?
3. **Quelle information compte le plus dans le bilan ?** Régularité, amplitude, douleur ?
4. **Les patients enverraient-ils leur bilan ?** Montrer l'app à 5 personnes ayant fait de la rééducation.

## Lancement

1. **Pilote** : 5 cabinets autour de Boulogne, 6 semaines, Rebond Pro offert (codes d'offre). Mesures : patients actifs, séances faites par rapport aux séances prescrites, bilans envoyés.
2. **Acquisition kinés** : écoles et instituts de formation en kinésithérapie (IFMK), syndicats et URPS, salons professionnels, groupes de kinés sur LinkedIn et Facebook.
3. **Bouche-à-oreille patient → kiné** : chaque bilan PDF porte « Généré avec Rebond » ; un kiné qui en reçoit découvre l'outil.
4. **App Store** : fiche double (patient / kiné), catégorie Santé et forme, vidéo de la séance guidée et du QR code.

## Mesures de succès

- Kinés abonnés, conversion essai → payant, rétention à 3 mois.
- Patients actifs par kiné, bilans reçus par kiné et par semaine.
- Séances faites par rapport aux séances prescrites (l'impact sur l'observance).

## Risques

| Risque | Parade |
|---|---|
| Être considéré comme un dispositif médical | « Suivi et conseils », jamais de diagnostic ; le kiné décide ; avis réglementaire avant un vrai lancement |
| Données de santé | Aucun serveur : les données vont directement du patient au kiné, sur son geste |
| Détection imparfaite des mouvements | Amplitude présentée « à titre indicatif » ; rien n'est compté quand la caméra voit mal |
| Les kinés n'ont pas le temps | Prescrire prend moins d'une minute ; le bilan se lit en 30 secondes |

## Pour le pitch (3 minutes)

1. Le problème, raconté du côté du kiné (30 s).
2. Démo (deux iPhone) : le kiné prescrit le programme par QR code → le patient le scanne et fait sa séance guidée par la caméra → il envoie son bilan → le kiné l'ouvre, voit la douleur et la régularité, ajuste le programme et montre le nouveau QR code (90 s).
3. 100 % Apple, 100 % sur l'appareil : Foundation Models, Vision, VisionKit, Swift Charts, StoreKit, App Intents (20 s).
4. Le modèle : gratuit pour le patient ; pour le kiné, gratuit jusqu'à 3 patients, puis un prix selon le volume : 10, 30 ou illimité (30 s).
5. La suite : pilote avec 5 cabinets (10 s).
