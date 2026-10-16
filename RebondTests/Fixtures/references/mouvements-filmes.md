# Mouvements filmés réels

Poses vues par Vision (`PoseRecording`, 15 images par seconde), extraites avec `Tools/References` des vidéos
filmées sur l'iPhone de l'équipe le 15 octobre (les vidéos elles-mêmes ne sont pas dans le dépôt).

| Fichier | Contenu |
|---|---|
| `film-elevation-bras.json` | élévation des deux bras sur le côté, 3 répétitions, pauses bras levés |
| `film-squat-bras-leves.json` | bras levés d'abord (préparation), puis 3 squats bras en l'air |
| `film-un-bras.json` | un bras : l'avant-bras se replie devant la poitrine, 3 fois |
| `film-flexion-coudes.json` | flexion des deux coudes |
| `film-jambe-tendue.json` | élévation de la jambe tendue |
| `seance-elevation-bras.json` | une série à la maison (enregistrement d'écran de la séance), 5 élévations des bras |

    sh Tools/References/build.sh
    Tools/References/references poses <vidéo> <sortie.json> [--session]
    Tools/References/references both <film.json> <seance.json>
