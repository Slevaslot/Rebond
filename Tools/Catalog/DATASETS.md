# Autres jeux de données Kinect : KIMORE et IRDS

Étude de faisabilité, pour élargir le catalogue au-delà des 10 mouvements d'UI-PRMD. Rien n'est intégré pour l'instant.
Les points marqués « à vérifier » n'ont pas pu être confirmés en ligne (article ou page de téléchargement inaccessible).

## Comparaison rapide

| | UI-PRMD (utilisé) | KIMORE | IRDS (IntelliRehabDS) |
|---|---|---|---|
| Capteur | Kinect v2 (et Vicon) | Kinect v2 | Kinect (25 articulations, donc probablement v2 ; à vérifier) |
| Personnes | 10 sujets sains | 78 : 44 sains, 34 patients (AVC, Parkinson, lombalgie) | 29 : 15 patients, 14 sains |
| Exercices | 10 | 5, pour le bas du dos | 9 gestes (liste à vérifier) |
| Squelette | 22 articulations, positions relatives + angles d'Euler | 25 articulations Kinect v2, positions caméra en mètres + quaternions | 25 articulations, x y z + coordonnées image (dx, dy) |
| Cadence | 30 Hz | ~30 Hz (horodatage en 100 ns) | 30 Hz (à vérifier) |
| Répétitions | déjà découpées (1 fichier = 1 répétition) | **non découpées** : un enregistrement continu par sujet et exercice | déjà découpées (1 fichier = 1 répétition) |
| Étiquettes | correct / incorrect | score clinique par exercice (TS, PO, CF), pas par répétition | correct / incorrect, position assis ou debout |
| Licence | libre d'usage académique | « jeu de données libre » selon l'article ; licence précise à vérifier | CC BY 4.0 (code et données selon Zenodo) |
| Accès | GitHub (miroir) | lien dans l'article Capecci et al. 2019 | Zenodo 10.5281/zenodo.4610859 (41 Go avec profondeur ; squelettes seuls bien plus légers) |

## KIMORE

**Exercices.** Bras levés, inclinaison latérale du buste bras tendus, rotation du buste, rotation du bassin dans le plan horizontal, squat.
**Apport.** Trois exercices du dos que le catalogue n'a pas (inclinaison latérale, rotation du buste, rotation du bassin), un deuxième squat, et surtout des **patients réels** (mouvements plus petits, plus lents, comme à la maison).

**Adaptation nécessaire.**
1. **Lecture.** Trois CSV par exercice (`JointPosition…`, `JointOrientation…`, `TimeStamp…`). Positions : 25 × (x, y, z, confiance), en mètres. Valeurs manquantes à 0 (pas NaN) : les écarter. Certains fichiers ont une 101ᵉ colonne vide.
2. **Projection.** Positions déjà absolues (plus simple qu'UI-PRMD : pas d'angles d'Euler à recomposer). Même projection de face à 2,5 m que pour UI-PRMD.
3. **Articulations.** Ordre Kinect v2 : SpineBase (0), SpineMid, Neck, Head, ShoulderLeft (4), ElbowLeft, WristLeft, HandLeft, ShoulderRight (8), ElbowRight, WristRight, HandRight, HipLeft (12), KneeLeft, AnkleLeft, FootLeft, HipRight (16), KneeRight, AnkleRight, FootRight, SpineShoulder (20), HandTipLeft, ThumbLeft, HandTipRight, ThumbRight. Correspondance avec `PoseMeasure` directe (hanches, genoux, chevilles, épaules, coudes, poignets ; cou = milieu des épaules comme pour Vision ; la tête peut tenir lieu de nez).
4. **Découpage.** Enregistrements continus : les découper en répétitions (le comptage par la vidéo du film de référence le fait déjà) ou les utiliser tels quels, comme une vidéo filmée chez le kiné. C'est en fait plus proche du cas réel.
5. **Étiquettes.** Pas de correct / incorrect par répétition : utiliser le groupe (sain ou patient) et le score clinique global comme indication de qualité.
6. **Mesures.** Les rotations (buste, bassin) se voient mal de face en 2D : ajouter des mesures (largeur apparente des épaules et des hanches, qui diminue quand on tourne) avant de les ajouter au catalogue.

**Risque.** Le squat KIMORE et celui d'UI-PRMD seront deux signatures du même exercice : les fusionner en un seul « Squat » avec des bandes plus larges.

## IRDS (IntelliRehabDS)

**Apport.** Des **patients**, des gestes faits **assis ou debout** (position étiquetée), un label correct / incorrect par répétition, une licence claire (CC BY 4.0). Les noms des 9 gestes sont dans une image du dépôt et dans l'article (inaccessible ici) : à relire avant de choisir.

**Adaptation nécessaire.**
1. **Lecture.** Un fichier par répétition ; nom `patient_date_geste_répétition_correct_position`. Une ligne par image : numéro d'image, index du corps, horodatage, puis 25 × (nom, état de suivi, x, y, z, dx, dy). Garder le corps le plus fréquent (plusieurs personnes peuvent apparaître). `correct` : 1 correct, 2 incorrect, 3 à ignorer.
2. **Projection.** Positions 3D absolues : même projection de face. Les `dx, dy` (coordonnées image, à confirmer) permettraient même de se passer de la projection.
3. **Articulations.** 25 articulations nommées dans le fichier : correspondance par nom.
4. **Position assise.** Notre mesure de position (hauteur des hanches en longueur de jambe) devra être validée sur leurs gestes assis : c'est justement ce qui manque à UI-PRMD (seul l'assis-debout passe par la position assise).

## Recommandation

1. **IRDS d'abord** : licence claire, répétitions déjà découpées, patients réels, positions assise et debout. Peu de travail de conversion (un lecteur de fichier et la correspondance des articulations), à faire dans `Tools/Catalog` à côté de `kinect.swift`.
2. **KIMORE ensuite**, pour les exercices du dos, après avoir ajouté les mesures de rotation du buste et du bassin.
3. Dans les deux cas, garder la **séparation par personne** pour l'entraînement et le test, et rejouer les tests de reconnaissance : un nouveau jeu peut créer de nouvelles confusions (bras levés de KIMORE contre abduction et scaption d'UI-PRMD).

## Sources

- KIMORE : Capecci et al., *The KIMORE Dataset*, IEEE TNSRE 27(7), 2019, DOI 10.1109/TNSRE.2019.2923060 ; [ResearchGate](https://www.researchgate.net/publication/333791841_The_KIMORE_Dataset_KInematic_Assessment_of_MOvement_and_Clinical_Scores_for_Remote_Monitoring_of_Physical_REhabilitation) ; format lu dans [KiMoRe_wrapper](https://github.com/petteriTeikari/KiMoRe_wrapper).
- IRDS : Miron et al., *Data* 6(5), 46, 2021, DOI 10.3390/data6050046 ; [Zenodo](https://zenodo.org/records/4610859) ; format lu dans le code de [intellirehabds](https://github.com/alina-miron/intellirehabds).
- Comparaisons UI-PRMD / KIMORE : [Taylor & Francis 2025](https://www.tandfonline.com/doi/full/10.1080/24751839.2025.2454053).
