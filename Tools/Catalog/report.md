# Catalogue d'exercices – rapport

UI-PRMD Kinect (University of Idaho), 10 mouvements, vue de face simulée à 2,5 m, 15 images/s. Signatures : personnes 1–6 (mouvements corrects) ; réglage : 7–8 ; test : 9–10.

Enregistrements mesurés : 2000.

## Signatures

| Exercice | Mesures principales | Plan | Position | Côtés | s/rép. |
|---|---|---|---|---|---|
| Squat | hauteur de la cheville, hauteur des hanches, hauteur de la cheville | sagittal | mixed | deux | 1.6 |
| Montée de genou (enjambement) | hauteur du genou, hanche, hauteur de la cheville | unknown | standing | un | 1.0 |
| Fente avant | hauteur des hanches, genou, hauteur de la cheville | sagittal | mixed | deux | 1.5 |
| Fente latérale | hauteur de la cheville, décalage des hanches, hauteur des hanches | frontal | mixed | deux | 1.8 |
| Assis-debout | hauteur de la cheville, hauteur des hanches, hauteur de la cheville | sagittal | mixed | deux | 2.0 |
| Élévation de la jambe tendue | hauteur de la cheville, écart des pieds, hauteur du genou | frontal | standing | un | 1.0 |
| Élévation latérale d'un bras | hauteur du poignet | frontal | standing | un | 1.7 |
| Extension de l'épaule | hauteur du poignet, longueur apparente du bras, écart du poignet | sagittal | standing | un | 0.9 |
| Rotation de l'épaule | hauteur du poignet, coude | sagittal | standing | un | 1.1 |
| Élévation du bras en diagonale | hauteur du poignet | frontal | standing | un | 1.4 |

## Paires proches (futures confusions)

| Exercice | Exercice | Distance |
|---|---|---|
| shoulder-abduction | scaption | 0.86 |
| squat | sit-to-stand | 1.11 |
| forward-lunge | side-lunge | 1.37 |
| hurdle-step | leg-raise | 1.42 |
| shoulder-abduction | shoulder-extension | 1.57 |
| squat | side-lunge | 1.76 |
| shoulder-abduction | shoulder-rotation | 1.98 |
| hurdle-step | forward-lunge | 2.32 |

## Présélection par signatures

| Jeu | Correct top 1 | Correct top 5 | Incorrect top 1 | Incorrect top 5 |
|---|---|---|---|---|
| validation (7–8) | 84 % | 100 % | 40 % | 98 % |
| test (9–10) | 91 % | 100 % | 42 % | 98 % |

Matrice de confusion (test, corrects ; ligne = vrai, colonne = choisi) :

| | m1 | m2 | m3 | m4 | m5 | m6 | m7 | m8 | m9 | m10 |
|---|---|---|---|---|---|---|---|---|---|---|
| m1 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| m2 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| m3 | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| m4 | 0 | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 |
| m5 | 0 | 0 | 0 | 7 | 13 | 0 | 0 | 0 | 0 | 0 |
| m6 | 0 | 9 | 0 | 0 | 0 | 11 | 0 | 0 | 0 | 0 |
| m7 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 0 | 0 |
| m8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 0 |
| m9 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 18 | 0 |
| m10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20 |

## Présélection par voisins

| Jeu | Correct top 1 | Correct top 5 | Incorrect top 1 | Incorrect top 5 |
|---|---|---|---|---|
| validation (7–8) | 92 % | 99 % | 66 % | 100 % |
| test (9–10) | 96 % | 100 % | 66 % | 100 % |

Matrice de confusion (test, corrects ; ligne = vrai, colonne = choisi) :

| | m1 | m2 | m3 | m4 | m5 | m6 | m7 | m8 | m9 | m10 |
|---|---|---|---|---|---|---|---|---|---|---|
| m1 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| m2 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| m3 | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| m4 | 0 | 0 | 0 | 20 | 0 | 0 | 0 | 0 | 0 | 0 |
| m5 | 1 | 0 | 0 | 0 | 19 | 0 | 0 | 0 | 0 | 0 |
| m6 | 0 | 8 | 0 | 0 | 0 | 12 | 0 | 0 | 0 | 0 |
| m7 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 0 | 0 |
| m8 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 0 |
| m9 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20 | 0 |
| m10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 20 |

## Hors catalogue

Seuil de distance (95 % des mouvements connus en dessous) : 1.81. Exercice retiré du catalogue rejeté : 30 %.
