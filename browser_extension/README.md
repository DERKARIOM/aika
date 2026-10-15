# Aika – Téléchargements (extension Chrome / Edge)

Quand vous cliquez sur un téléchargement dans Chrome ou Edge, l'extension le
confie à Aika, qui le télécharge avec plusieurs connexions, la pause et la
reprise (même après un redémarrage).

## Installation (mode développeur)

1. Dans Aika (Windows, macOS ou Linux) : **Télécharger depuis un lien →
   Options → Intégration navigateur**, activez l'option et copiez le
   **code d'appairage**.
2. Ouvrez `chrome://extensions` (ou `edge://extensions`), activez le
   **Mode développeur**, puis **Charger l'extension non empaquetée** et
   choisissez ce dossier `browser_extension`.
3. Cliquez sur l'icône Aika de la barre d'outils, collez le code puis
   **Enregistrer** : l'état passe à « Connecté à Aika ».

## Fonctionnement

1. Un téléchargement démarre dans le navigateur : l'extension le met en
   pause et envoie à Aika son lien final (après les redirections), son nom et
   sa taille.
2. Aika vérifie que le lien sert bien un fichier, puis l'ajoute à sa file :
   le navigateur annule alors sa propre copie.
3. Si Aika est fermée, refuse le lien ou ne peut pas l'atteindre (fichier
   qui exige la session du site, page web…), le navigateur continue le
   téléchargement normalement. Aucun téléchargement n'est perdu.

Options du popup : activer / désactiver, taille minimale (1 Mo par défaut,
les petits fichiers restent dans le navigateur), navigation privée.

## Sécurité et vie privée

- Seuls le lien, le nom et la taille du fichier sont envoyés, et uniquement à
  Aika sur cet ordinateur (`http://127.0.0.1:53319`). Les cookies, le contenu
  des pages et l'historique ne sont jamais lus.
- Permissions : `downloads` (voir et reprendre les téléchargements) et
  `storage` (options). Aucune permission sur les sites web.
- Côté Aika, le récepteur n'écoute que l'ordinateur local, refuse toute
  requête venant d'une page web (`Origin`, `Host`), exige le code
  d'appairage et applique au lien les protections habituelles (pas
  d'adresse locale, redirections vérifiées).
- Le code peut être régénéré à tout moment dans Aika ; l'extension doit
  alors être appairée à nouveau.

## Publication

Le même dossier convient au Chrome Web Store et à Microsoft Edge Add-ons
(zip du contenu du dossier). La publication se fait avec le compte
développeur du propriétaire du projet.
