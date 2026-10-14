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

## Deux offres pour le kiné

| | Gratuite | Rebond Pro |
|---|---|---|
| Prescrire un programme en QR code | ✓ | ✓ |
| Suivre ses patients (régularité, répétitions, amplitude, douleur, alertes) | **3 patients** | **Illimité** |
| Modifier un programme et le renvoyer | ✓ (nouveau QR code) | ✓ **à distance, sans QR code** |
| Patients liés en permanence, bilans reçus automatiquement | — | ✓ |
| Données | Sur l'iPhone, aucun serveur | Serveur certifié HDS (hébergeur de données de santé) |
| Prix | 0 € | 19,99 € HT / mois ou 199 € HT / an, 1 mois offert |

Le patient ne paie jamais.

**Pourquoi ce découpage :**
- L'offre gratuite fait adopter l'outil : le kiné l'essaie sur 3 patients, avec toutes les fonctions locales.
- Le moment de payer est naturel : au 4ᵉ patient, il a déjà vu la valeur.
- Le serveur apporte ce que le local ne peut pas faire (liens permanents, bilans automatiques, modifications à distance) et justifie l'abonnement.

**État pour le hackathon :**
- Le build App Store contient l'offre gratuite et Rebond Pro en patients illimités (StoreKit 2). L'écran d'achat ne promet que ce qui existe déjà.
- La version connectée est un **prototype de démo** (`Server/`, patients fictifs) présent seulement dans les versions installées depuis Xcode. En production, elle sera hébergée chez un hébergeur certifié HDS (AWS, Azure, OVHcloud…), avec consentement du patient et vérification du kiné (RPPS).

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
2. Démo (deux iPhone, version connectée) : le kiné invite le patient par QR code → le patient fait sa séance guidée par la caméra → le bilan arrive chez le kiné → le kiné ajuste le programme → il apparaît sur l'iPhone du patient (90 s).
3. 100 % Apple, 100 % sur l'appareil : Foundation Models, Vision, VisionKit, Swift Charts, StoreKit, App Intents (20 s).
4. Le modèle : gratuit pour le patient ; pour le kiné, gratuit jusqu'à 3 patients, puis Rebond Pro connecté (30 s).
5. La suite : hébergement HDS et pilote avec 5 cabinets (10 s).
