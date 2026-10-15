# Vidéos iPhone annotées

Une vidéo par exercice filmé, de face, corps entier, immobile au début. Le nom du fichier donne l'exercice attendu :

    <id du catalogue>__<description libre>.mov      ex. squat__demi-squat-salon.mov
    hors-catalogue__<description>.mov               mouvement absent du catalogue : doit sortir « non reconnu »

Ids du catalogue : squat, hurdle-step, forward-lunge, side-lunge, sit-to-stand, leg-raise, shoulder-abduction,
shoulder-extension, shoulder-rotation, scaption.

Les tests (`RecognitionTests`) rejouent tout le pipeline sur ces vidéos, sans caméra, et comparent la précision
avec celle des données Kinect. Vision ne détecte pas le corps dans le simulateur : ces tests-là tournent sur iPhone.
