## 1.1.4

- Messagerie instantanée entièrement revue : messages chiffrés directement entre les appareils (TLS avec vérification d'identité), accusés de réception et de lecture, indicateur « en train d'écrire », messages en attente renvoyés automatiquement dès que l'appareil revient sur le réseau.
- Nouvelle interface de discussion moderne : bulles, regroupement des messages, séparateurs de jours, aperçus d'images, bouton « derniers messages ».
- Envoi de fichiers dans une discussion avec progression, vitesse et temps restant dans la bulle ; annulation d'un envoi (le message disparaît des deux côtés) ; glisser-déposer sur ordinateur ; envoi de plusieurs fichiers à la fois.
- Réponses à un message, réactions par emoji, modification d'un message envoyé et suppression « pour moi » ou « pour tous ».
- Recherche dans toutes les discussions (texte et noms de fichiers).
- Envoi de gros fichiers (vidéos de plusieurs centaines de Mo) depuis Android sans plantage.
- Fiabilité : un fichier interrompu n'est plus jamais considéré comme reçu, vérification de la taille des fichiers reçus, corrections de blocages d'envoi.

## 1.0.3

- Nouveau : vérification et mise à jour d'Aika directement depuis l'application sur Android, via le système officiel Google Play In-App Updates (mise à jour en arrière-plan ou installation guidée selon l'importance de la mise à jour, jamais de téléchargement d'APK externe).
- Thème sombre activé par défaut.
- Ajout du logo Aika à côté du nom de l'application dans la barre latérale des versions bureau (macOS, Windows, Linux).
- Amélioration de l'écran « Partager via un lien » : plus facile à trouver, interface personnalisée, et affichage automatique d'une demande d'autorisation (nom et adresse IP de l'appareil demandeur, boutons Accepter/Refuser) lorsqu'un appareil souhaite se connecter.
- Personnalisation de la page web générée lors d'un partage de fichiers via un lien local.

## 1.0.2

- Correction d'un plantage au premier lancement sur Windows lorsque l'application est installée dans un dossier protégé (ex. `C:\Program Files`) : l'app tentait d'écrire ses réglages au mauvais endroit et se fermait immédiatement avec une erreur d'accès refusé.

## 1.0.0

Version initiale d'Aika.

- Transfert de fichiers, dossiers et messages entre appareils proches, directement sur le réseau local — aucune connexion Internet requise.
- Découverte automatique des appareils à proximité, avec connexion rapide par QR Code.
- Historique de conversation conservé localement sur l'appareil.
- Identité visuelle et interface propres à Aika.

Aika s'appuie sur la technologie open source LocalSend (Apache License 2.0).
