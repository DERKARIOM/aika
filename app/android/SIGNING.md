# Signature de la build Android (release)

Ce document explique comment configurer la signature de la build de release
Android d'Aika, sans jamais exposer de secret dans Git.

## État actuel

Un fichier `android/aika_key.jks` existe déjà dans ce dépôt local. **Ce fichier
n'est pas suivi par Git** (voir `android/.gitignore`, qui exclut `**/*.jks`,
`**/*.keystore` et `key.properties`) et ne l'a jamais été — vérifié via
`git log --all -- android/aika_key.jks` (aucun résultat).

Si vous connaissez déjà le mot de passe et l'alias de ce keystore, passez
directement à l'étape « Configurer key.properties » ci-dessous.

Si vous ne connaissez pas ce mot de passe (par exemple si ce fichier a été
généré lors d'une session précédente dont vous n'avez pas gardé les
identifiants), il est **impossible de le récupérer** : un keystore Android
sans mot de passe n'est pas exploitable. Il faudra alors générer un nouveau
keystore (étape « Générer un nouveau keystore » ci-dessous) — attention
toutefois : si `aika_key.jks` a déjà servi à publier une version sur le Google
Play Store, un changement de keystore empêchera de mettre à jour cette fiche
existante (Google Play exige la même signature pour toutes les mises à jour
d'une application, sauf usage de Play App Signing avec upload key rotation).

## Générer un nouveau keystore (si nécessaire)

```bash
keytool -genkey -v -keystore aika_key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias aika
```

Exécutez cette commande **dans le dossier `android/`** de votre machine
(jamais dans un environnement partagé). `keytool` vous demandera un mot de
passe de keystore, un mot de passe de clé, et des informations d'identité
(nom, organisation, etc.) — notez précieusement ces mots de passe : ils ne
sont récupérables nulle part si vous les perdez, et vous ne pourrez plus
jamais publier de mise à jour de l'app sur Google Play sans eux (sauf si Play
App Signing est activé, qui permet une procédure de récupération via la
Play Console).

## Configurer key.properties

1. Copiez `android/key.properties.example` vers `android/key.properties`
   (même dossier).
2. Remplacez les valeurs `REPLACE_WITH_...` par vos vraies valeurs
   (mot de passe du keystore, mot de passe de la clé, alias).
3. Vérifiez que `storeFile` pointe bien vers votre fichier `.jks` (le chemin
   est relatif à `android/app/`, donc `../aika_key.jks` si le fichier est à
   la racine de `android/`).

`android/app/build.gradle` lit automatiquement ce fichier au moment du build
release (`signingConfigs.release`) — s'il est absent, la build debug
fonctionne normalement mais la build release échouera (`storeFile` sera
`null`).

## Ne jamais faire

- Ne jamais committer `key.properties`, `aika_key.jks`, ou tout autre
  fichier `.jks`/`.keystore`.
- Ne jamais coller un mot de passe ou une clé privée dans un message de
  commit, une Pull Request, un fichier de configuration CI en clair, ou une
  conversation avec un assistant IA (y compris celle-ci).
- Pour une intégration continue (GitHub Actions, etc.), stockez le keystore
  encodé en base64 et les mots de passe dans des **secrets** du dépôt
  (`Settings > Secrets and variables > Actions`), jamais dans le code source.
  Ce dépôt contient déjà un workflow `.github/workflows/release.yml` hérité
  de LocalSend qu'il faudra adapter séparément (hors périmètre de cette
  tâche) avant de l'utiliser pour publier Aika.

## Vérifier qu'aucun secret n'a fui

Avant tout `git push`, vous pouvez vérifier qu'aucun de ces fichiers n'est
suivi par Git :

```bash
git status --porcelain android/key.properties android/aika_key.jks android/*.jks
git log --all --oneline -- android/key.properties android/aika_key.jks
```

Les deux commandes doivent retourner un résultat vide (aucun fichier suivi,
aucun commit historique les contenant).
