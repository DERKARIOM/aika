# Release iOS d'Aika (CI/CD GitHub Actions)

Ce document explique comment fonctionne la pipeline iOS d'Aika (`.github/workflows/ios-release.yml`),
comment récupérer et installer l'application sur un iPhone **sans Mac local et sans compte
Apple Developer payant**, et ce qui change le jour où un compte payant est disponible.

## Ce que produit la pipeline aujourd'hui

Un fichier `Aika.ipa` **non signé** (`Unsigned`). C'est normal et attendu tant qu'aucun compte
Apple Developer payant n'est configuré : Apple exige une identité de signature valide pour
produire un IPA signé, et un Apple ID personnel gratuit ne peut pas signer en mode automatisé
(headless) sur un serveur CI — il exige une session interactive dans Xcode. La CI ne contourne
pas cette limitation : elle construit l'app sans tenter de la signer, et c'est **Sideloadly**
ou **AltStore**, sur ta machine, qui la signent localement avec ton propre Apple ID au moment
de l'installation.

## Déclencher un build

### Manuellement

1. Va sur l'onglet **Actions** du dépôt GitHub.
2. Choisis le workflow **iOS Release (non signé)**.
3. Clique **Run workflow** (branche `main`, ou celle de ton choix).

Le build utilisera la version présente dans `pubspec.yaml`.

### Via un tag de release

Le préfixe est **`ios-v`**, volontairement différent de `v` (réservé à la release desktop
Linux/Windows/macOS existante, `.github/workflows/release.yml`) et cohérent avec le `macos-v`
déjà utilisé pour macOS (voir `app/docs/macos-release.md`). Ça évite qu'un même tag déclenche
plusieurs pipelines qui n'ont rien à voir entre elles.

Le numéro après `ios-v` doit être **identique** à `version:` dans `app/pubspec.yaml` (sans le
`+build`), sinon le job `validate` échoue immédiatement avec un message explicite plutôt que de
partir sur une version incohérente.

```
git tag ios-v1.2.0
git push origin ios-v1.2.0
```

Ce tag déclenche automatiquement :
- le build de l'IPA avec `MARKETING_VERSION = 1.2.0` ;
- la création d'une **GitHub Release en brouillon (draft)** intitulée `Aika iOS v1.2.0`, avec
  `Aika-1.2.0.ipa` en pièce jointe — à vérifier puis publier manuellement depuis l'onglet
  **Releases** de GitHub.

## Récupérer le résultat

### Depuis un run manuel (Artifact)

1. Ouvre le run terminé dans l'onglet **Actions**.
2. Descends jusqu'à la section **Artifacts** en bas de page.
3. Télécharge `Aika-<version>-<build>-unsigned` (fichier `.zip` contenant `Aika.ipa`).
4. Conservé 90 jours par GitHub, puis supprimé automatiquement.

### Depuis un tag (GitHub Release)

Va dans l'onglet **Releases** du dépôt, ouvre la release correspondant au tag, et télécharge
directement `Aika-<version>.ipa`.

## Installer le .ipa depuis Windows

### Avec Sideloadly

1. Installe [Sideloadly](https://sideloadly.io/) sur Windows et [iTunes/Apple Devices](https://support.apple.com/HT210384) pour les pilotes USB.
2. Branche l'iPhone 11 Pro en USB et fais-lui confiance sur le téléphone si demandé.
3. Ouvre Sideloadly, glisse le fichier `Aika.ipa` téléchargé.
4. Renseigne ton Apple ID (identifiant + mot de passe) — Sideloadly l'utilise uniquement pour
   demander à Apple un certificat de signature gratuit, il ne l'envoie à personne d'autre.
5. Clique **Start** : Sideloadly resigne l'IPA localement puis l'installe sur l'iPhone.
6. Sur l'iPhone : **Réglages > Général > VPN et gestion de l'appareil**, fais confiance au
   profil développeur associé à ton Apple ID.

### Avec AltStore

1. Installe [AltServer](https://altstore.io/) sur Windows, puis l'app **AltStore** sur l'iPhone
   via AltServer (câble USB requis la première fois).
2. Sur Windows, dans AltServer, choisis **Install .ipa** (ou glisse le fichier dans AltStore
   sur l'iPhone une fois installé) et sélectionne `Aika.ipa`.
3. AltServer resigne l'IPA avec ton Apple ID et l'installe.
4. Comme pour Sideloadly, il faut faire confiance au profil développeur dans les réglages.

## Limites d'un Apple ID gratuit (Personal Team)

- L'app expire au bout de **7 jours** : passé ce délai elle ne se lance plus, il faut la
  réinstaller (Sideloadly/AltStore permettent de le refaire rapidement). AltStore propose un
  mécanisme de réinstallation automatique en Wi-Fi si AltServer tourne sur un PC du même réseau.
- Maximum **3 app IDs actifs simultanément** par Apple ID gratuit sur 7 jours glissants.
- Pas de notifications push, pas de certains entitlements avancés (Sign in with Apple complet,
  certains services iCloud, etc.).
- Pas de distribution TestFlight, pas de soumission App Store.
- Un seul appareil à la fois n'est pas une limite en soi, mais chaque appareil doit être
  enregistré (ce que Sideloadly/AltStore font automatiquement lors de l'installation).

## À propos du Team ID déjà présent dans le projet (MM9Z35FS2F)

`ios/Runner.xcodeproj/project.pbxproj` contient un `DEVELOPMENT_TEAM = MM9Z35FS2F` codé en dur.
Ce Team ID n'appartient pas à ce projet — c'est très probablement un reliquat du fork LocalSend
d'origine — et cette pipeline ne s'en sert pas : `--no-codesign` désactive la signature avant même
que ce champ ne soit consulté. Ne pas tenter de signer avec ce Team ID, y compris manuellement :
personne ici n'en détient les identifiants.

⚠️ `app/docs/macos-release.md` (rédigé lors d'une session précédente) part du principe que ce
même Team ID correspond à un compte Apple Developer payant actif et détaille une procédure de
signature « Developer ID Application » sur cette base. Cette hypothèse s'est révélée fausse — la
procédure macOS qui y est décrite ne fonctionnera pas telle quelle tant qu'un vrai compte payant
(appartenant réellement à ce projet) n'existe pas. Ce point n'a pas été corrigé ici : il concerne
la pipeline macOS, pas iOS, mais mérite d'être révisé si la release macOS est reprise.

## Ce qui change avec un compte Apple Developer payant (99 $/an)

- L'app peut être signée avec un vrai certificat de distribution : plus de limite de 7 jours.
- Possibilité de distribuer via **TestFlight** ou l'**App Store**.
- La CI peut produire un IPA **réellement signé**, installable directement sans Sideloadly/AltStore
  (via un profil de provisionnement ad-hoc enregistrant les UDID des appareils autorisés, ou
  via l'App Store).
- Accès aux entitlements avancés (push, iCloud complet, etc.) si Aika en a besoin un jour.

### Configurer les secrets GitHub le moment venu

Dans **Settings > Secrets and variables > Actions** du dépôt, ajouter :

| Secret | Contenu |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Le certificat de distribution (`.p12`) encodé en base64 (`base64 -i cert.p12`) |
| `APPLE_CERTIFICATE_PASSWORD` | Le mot de passe du `.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Le profil de provisionnement (`.mobileprovision`) encodé en base64 |
| `KEYCHAIN_PASSWORD` | Un mot de passe temporaire pour le trousseau créé pendant le run CI (une valeur aléatoire suffit) |
| `APPLE_TEAM_ID` | Le Team ID du compte Apple Developer payant |
| `BUNDLE_IDENTIFIER` | `com.naniger.aika` |

Le fichier `ios-release.yml` contient déjà, en commentaire tout en bas, la marche à suivre
précise pour brancher ces secrets (import du certificat dans un trousseau temporaire, dépôt du
profil de provisionnement, remplacement de `flutter build ios --no-codesign` par
`flutter build ipa --export-options-plist=...`). Rien de tout cela n'est actif tant que ces
secrets n'existent pas — le workflow ne les référence pas pour éviter un échec si absents.

## Problèmes fréquents

- **« Code de version déjà utilisé » côté Play Store** : sans rapport avec cette pipeline iOS
  (spécifique à Android), voir l'historique du projet.
- **`pod install` échoue en CI** : généralement un souci de cache CocoaPods obsolète sur le
  runner — relancer le job (`--repo-update` force déjà un rafraîchissement des specs).
- **Le build Rust (`cargokitCargoBuild...`) échoue sur le runner macOS** : les runners macOS
  GitHub-hébergés viennent avec Rust préinstallé, et cargokit gère lui-même l'ajout de la
  cible `aarch64-apple-ios` (aucune étape dédiée n'a été nécessaire pour les builds Linux/
  Windows/macOS existants d'Aika, voir `.github/workflows/release.yml`). `CARGOKIT_VERBOSE=1`
  est activé sur l'étape de build pour avoir des logs détaillés en cas d'échec. Si ça bloque
  quand même, c'est probablement une variante du même souci déjà rencontré côté build Android
  sur la machine Windows de développement — à comparer en priorité.
- **Sideloadly/AltStore refusent l'installation** : vérifier que l'iPhone fait bien confiance
  au profil développeur dans **Réglages > Général > VPN et gestion de l'appareil**, et que
  l'horloge de l'iPhone est à jour (un décalage d'horloge invalide les certificats).
- **L'app s'arrête de fonctionner après 7 jours** : normal avec un Apple ID gratuit, il faut
  refaire l'installation (voir plus haut).
