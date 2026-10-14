# Serveur de démo Rebond

Prototype de la **version connectée de Rebond Pro**, pour le pitch uniquement : le kiné et ses patients sont liés, le bilan arrive tout seul après chaque séance, et le kiné modifie le programme à distance.

**Patients fictifs uniquement.** De vraies données de santé doivent être hébergées chez un hébergeur certifié HDS. Ce serveur n'est utilisé que par les versions de développement (installées depuis Xcode) ; le build App Store n'en contient pas une ligne.

## Lancer

```bash
python3 Server/server.py
```

Le serveur affiche son adresse (par exemple `http://mon-mac.local:8080`). Le Mac et les deux iPhone doivent être sur le même réseau. Si le Wi-Fi de l'événement isole les appareils, utiliser le partage de connexion d'un iPhone pour les trois.

## Démo

1. **iPhone du kiné** : Espace kiné → Version connectée → saisir l'adresse → « Inviter un patient » affiche un QR code.
2. **iPhone du patient** : scanner le QR code avec l'appareil photo → Rebond s'ouvre, l'iPhone est lié au kiné.
3. Le patient fait une séance → son bilan apparaît chez le kiné (marqué « connecté »).
4. Le kiné ouvre la fiche du patient → « Modifier le programme » → « Envoyer » → quelques secondes plus tard, l'iPhone du patient propose le nouveau programme.

Les données sont dans `Server/demo-data.json` (supprimer le fichier pour repartir de zéro).
