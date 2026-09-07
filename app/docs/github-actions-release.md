# Release desktop Aika via GitHub Actions

Ce document décrit le pipeline automatisé `.github/workflows/release.yml` qui construit et publie une
Release GitHub (en brouillon) pour Aika sur Linux (`.deb`), Windows (installeur Inno Setup, non signé) et
macOS (`.dmg`, non signé), à partir d'un tag Git.

## 1. Comment couper une release

Depuis votre machine, sur `main`, à jour :

```bash
# 1. Bump la version (les deux fichiers doivent être identiques)
#    - app/pubspec.yaml            → version: X.Y.Z+N
#    - support/scripts/compile_windows_exe-inno.iss → #define MyAppVersion "X.Y.Z"
#    (ci.yml échoue sur chaque push/PR si ces deux valeurs divergent)

# 2. Mettez à jour app/assets/CHANGELOG.md avec les changements de cette version.

# 3. Commit, push, puis créez et poussez le tag
git add app/pubspec.yaml support/scripts/compile_windows_exe-inno.iss app/assets/CHANGELOG.md
git commit -m "chore: bump version to X.Y.Z"
git push
git tag vX.Y.Z
git push origin vX.Y.Z
```

Le push du tag `vX.Y.Z` déclenche `release.yml`. Rien d'autre ne déclenche ce workflow (pas de
`workflow_dispatch` volontairement : le tag est la seule source de vérité pour "cette version est prête à
être publiée").

## 2. Ce que fait le pipeline

```
push tag vX.Y.Z
      │
      ▼
   validate        — vérifie le format du tag (vX.Y.Z strict), compare sa version à
 (ubuntu-24.04)       app/pubspec.yaml (échoue si différent), lance flutter analyze + flutter
      │               test une seule fois. Utilise le code généré déjà commité dans le dépôt
      │               (comme ci.yml) plutôt que de le régénérer : une régénération via
      │               `build_runner` dans ce job a produit, lors du premier run réel, un
      │               `android_channel.mapper.dart` incomplet (symboles "undefined" en
      │               aval) alors que le fichier commité est correct — régénérer en CI s'est
      │               donc avéré plus risqué que de faire confiance au code déjà généré.
      │
  ┌───┼──────────────┬──────────────────┐
  │                  │                  │
  ▼                  ▼                  ▼
build-linux      build-windows      build-macos
(ubuntu-24.04)   (windows-latest)   (macos-latest)
  │                  │                  │
flutter_distributor  flutter build    flutter build macos --release
  → .deb              windows         + vérification binaire universel
                     + DLL VC++         (lipo -info, doit contenir arm64 ET x86_64)
                     + Inno Setup      + macos/scripts/build_dmg.sh (non signé)
                       (non signé)
  │                  │                  │
  └────────┬─────────┴──────────────────┘
           ▼
      checksums        — rassemble les 3 fichiers, calcule SHA256SUMS.txt
           ▼
   publish-release     — crée une Release GitHub en BROUILLON (draft), avec les 3
 (ubuntu-24.04)          fichiers + SHA256SUMS.txt + des notes d'installation

```

Chaque étape de build vérifie explicitement que le fichier attendu existe avant de continuer (le
pipeline échoue bruyamment plutôt que de publier une release incomplète en silence).

## 3. Pourquoi une Release en brouillon

`publish-release` crée toujours la Release en **draft**. Rien n'est visible publiquement tant que vous ne
l'avez pas publiée manuellement depuis l'onglet "Releases" du dépôt GitHub — l'occasion de vérifier les 3
fichiers (les télécharger, les lancer) avant de les rendre publics.

## 4. Ce qui n'est PAS fait (limitations actuelles, assumées)

- **Aucune signature de code**, sur aucune des 3 plateformes :
  - Windows : l'installeur Inno Setup n'est pas signé. SmartScreen affichera un avertissement au premier
    lancement (contournable via "Informations complémentaires" → "Exécuter quand même").
  - macOS : le `.app`/`.dmg` ne sont ni signés ni notariés. Gatekeeper bloquera le premier lancement
    (contournable via clic droit → "Ouvrir"). La procédure de signature/notarisation manuelle existe déjà
    et est documentée dans `docs/macos-release.md`, mais n'est pas (encore) automatisée en CI — cela
    demanderait de stocker un certificat Apple Developer et un mot de passe d'application dans les secrets
    du dépôt, ce qui n'a pas été mis en place.
  - Linux : les `.deb` non signés sont la norme pour une distribution hors dépôt APT officiel ; rien à
    signer ici.
- **Pas de build ARM64** (Linux ni Windows ni macOS Intel) : seul `x86_64`/`x86-64` pour Linux et Windows,
  et le binaire "universel" (arm64 + x86_64 dans le même exécutable, vérifié par le job) pour macOS.
- **Pas de build Android/iOS** dans ce pipeline : il est strictement desktop (Linux/Windows/macOS). Le
  packaging Android existe ailleurs dans le dépôt (`fastlane/`, `support/scripts/compile_android_*`).

## 5. Ce qui a été remplacé

Le dépôt contenait déjà un `.github/workflows/release.yml` hérité tel quel du projet amont LocalSend :
déclenché manuellement (`workflow_dispatch`), il construisait un APK Android (nécessitant des secrets de
keystore), des `.tar.gz`/`.deb` x86_64 **et** arm64 (l'arm64 nécessite un runner self-hosted), un AppImage
et un `.zip` Windows — le tout encore nommé `LocalSend-*`. Il a été entièrement remplacé par ce nouveau
pipeline (déclenché par tag, uniquement `.deb`/installeur Windows/`.dmg`, branding Aika). Rien de cet
ancien workflow n'a été conservé ailleurs ; si l'automatisation Android/AppImage doit revenir un jour, elle
devra être réécrite (secrets de signature Android à reconfigurer, runner arm64 à provisionner).

`.github/workflows/ci.yml` (format/test/packaging sur push et PR vers `main`) n'a pas été modifié — il
continue de fonctionner indépendamment de `release.yml`, et son job "packaging" (qui compare la version de
`pubspec.yaml` à celle de `compile_windows_exe-inno.iss`) est désormais cohérent : avant cette session, il
comparait `1.0.1` (pubspec) à `1.17.0` (valeur LocalSend jamais mise à jour), donc il échouait probablement
déjà sur chaque push/PR vers `main`.

## 6. Risques connus, non vérifiables depuis ce dépôt

Rien de ce qui précède n'a pu être testé de bout en bout avant ce rapport (pas d'accès à un runner GitHub
Actions réel depuis cette session). Points les plus susceptibles de nécessiter un ajustement au premier
run réel :

- **`flutter_distributor package --platform linux --targets deb`** : cette commande exacte est déjà
  utilisée avec succès dans l'ancien `release.yml` (job `build_deb_x86_64`), donc la syntaxe est
  correcte — mais c'est la première fois qu'elle tourne avec `app/distribute_options.yaml` présent à côté
  (il ne devrait rien changer, la commande `package` lit `linux/packaging/deb/make_config.yaml`
  directement, mais à confirmer).
- **Inno Setup préinstallé sur `windows-latest`** : un garde-fou installe `innosetup` via `choco` si
  `ISCC.exe` est absent, mais cela n'a pas pu être vérifié en conditions réelles.
- **Compilation Linux/Windows d'Aika** : d'après l'audit précédent (`cicd-audit-2026-09.md`), ni Linux ni
  Windows n'ont jamais été buildés avec succès pour Aika à ce jour (seul macOS a un historique de build
  réussi) — ce pipeline sera donc le premier vrai test de compatibilité des dépendances mobile-first
  (`device_apps`, `gal`, `mobile_scanner`, `wechat_assets_picker`, `image_picker`, `in_app_purchase`) sur
  ces deux plateformes.
- **cargokit (Rust)** : aucune étape d'installation explicite de Rust n'a été ajoutée dans les jobs de
  build, sur la foi que `packages/localsend_isolates/rust_builder/cargokit` s'auto-provisionne (comme le
  suggère `ci.yml`, qui ne configure pas Rust explicitement). Chaque job de build (validate, build-linux,
  build-windows, build-macos) lance quand même `flutter pub get` dans
  `packages/localsend_isolates/rust_builder/cargokit/build_tool`, exactement comme `ci.yml` — sans cette
  étape (absente d'une version antérieure de ce fichier sur les jobs de build desktop), un job de build
  échouerait presque certainement sur `cargo`/`rustc` introuvable au moment de compiler l'extension
  native. Si ça échoue quand même, c'est le point à corriger en premier (ajouter un `actions-rs/toolchain`
  comme le faisait l'ancien `release.yml`).

## 7. Divergence de version Flutter restante

`.fvmrc` et `release.yml` sont désormais épinglés sur **Flutter 3.44.0** (la version confirmée par
`flutter --version` sur votre machine). `ci.yml` et `linux_build.yml` (non touchés, hors périmètre de cette
tâche) référencent encore `3.41.9`. Les deux versions sont compatibles avec les contraintes de
`pubspec.yaml` (`flutter: ^3.41.0`), donc rien n'est cassé, mais il pourrait être utile d'aligner
`ci.yml`/`linux_build.yml` sur 3.44.0 également, dans une prochaine tâche.
