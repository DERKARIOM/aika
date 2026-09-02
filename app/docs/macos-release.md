# Release macOS — Aika 1.0.0

Ce document décrit la procédure complète pour construire, signer, notariser, packager et publier la version macOS d'Aika en dehors du Mac App Store (distribution directe). Aucune étape ci-dessous ne demande ni ne stocke de secret dans le dépôt : chaque commande utilise vos propres identifiants, entrés localement sur votre Mac ou dans les secrets GitHub Actions du dépôt.

## 1. Prérequis

- Un Mac avec Xcode installé (le même que celui utilisé pour développer Aika).
- Flutter installé et à jour (`flutter doctor` sans erreur bloquante pour macOS).
- `create-dmg` installé : `brew install create-dmg`.
- Un compte Apple Developer actif, membre de l'équipe `MM9Z35FS2F` (Team ID déjà configuré dans le projet Xcode).
- Être connecté à ce compte Apple Developer dans Xcode (Xcode → Settings → Accounts).

## 2. Configuration Apple Developer

### 2.1 Certificat « Developer ID Application »

La distribution directe (hors Mac App Store) nécessite un certificat de signature de type **Developer ID Application**, différent du certificat « Apple Development » utilisé pour le débogage local.

Pour l'obtenir :
1. Ouvrez Xcode → Settings → Accounts → sélectionnez votre compte → « Manage Certificates… ».
2. Cliquez sur « + » → « Developer ID Application ». Xcode le génère et l'installe dans votre trousseau (Keychain).
3. Vérifiez qu'il apparaît : `security find-identity -v -p codesigning` doit lister une entrée `Developer ID Application: <Votre nom/organisation> (MM9Z35FS2F)`.

Le projet (`macos/Runner.xcodeproj/project.pbxproj`) a déjà été mis à jour pour utiliser cette identité en configuration **Release** (pour la cible `Runner` et la cible `ShareExtension`), tout en gardant `Apple Development` pour `Debug`/`Profile` — pas de changement supplémentaire nécessaire ici.

### 2.2 Mot de passe d'application (pour la notarisation)

La notarisation via `notarytool` nécessite un **mot de passe spécifique à l'application**, pas votre mot de passe Apple ID :
1. Rendez-vous sur [appleid.apple.com](https://appleid.apple.com) → Sécurité → Mots de passe pour applications → Générer un mot de passe.
2. Conservez-le dans un gestionnaire de mots de passe (jamais dans le dépôt).

## 3. Build

Depuis le dossier `app/` :

```bash
flutter clean
flutter pub get
flutter build macos --release
```

Résultat attendu : `build/macos/Build/Products/Release/Aika.app`.

Vérifications rapides :
```bash
# Bundle Identifier effectif
defaults read "$(pwd)/build/macos/Build/Products/Release/Aika.app/Contents/Info.plist" CFBundleIdentifier
# → com.naniger.aika

# Version
defaults read "$(pwd)/build/macos/Build/Products/Release/Aika.app/Contents/Info.plist" CFBundleShortVersionString
defaults read "$(pwd)/build/macos/Build/Products/Release/Aika.app/Contents/Info.plist" CFBundleVersion
# → 1.0.0 / 1
```

## 4. Signature

```bash
APP_PATH="build/macos/Build/Products/Release/Aika.app"
IDENTITY="Developer ID Application: <Votre nom/organisation> (MM9Z35FS2F)"

codesign --force --deep --options runtime \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

`--options runtime` active le Hardened Runtime (déjà requis par `ENABLE_HARDENED_RUNTIME = YES` dans le projet), condition nécessaire à la notarisation.

## 5. Notarisation

```bash
APP_PATH="build/macos/Build/Products/Release/Aika.app"
ditto -c -k --keepParent "$APP_PATH" /tmp/Aika-notarize.zip

xcrun notarytool submit /tmp/Aika-notarize.zip \
  --apple-id "<votre Apple ID>" \
  --password "<mot de passe d'application généré en 2.2>" \
  --team-id "MM9Z35FS2F" \
  --wait
```

Si la notarisation échoue, consultez le rapport détaillé :
```bash
xcrun notarytool log <submission-id> --apple-id "<votre Apple ID>" --team-id "MM9Z35FS2F" --password "<mot de passe d'application>"
```

Une fois acceptée (« Accepted »), agrafez le ticket de notarisation à l'app (pour qu'elle fonctionne hors ligne au premier lancement) :
```bash
xcrun stapler staple "$APP_PATH"
```

Vérification finale Gatekeeper :
```bash
spctl -a -vvv "$APP_PATH"
# → doit afficher : accepted, source=Notarized Developer ID
```

## 6. Création du DMG

Un script prêt à l'emploi est fourni : `macos/scripts/build_dmg.sh`, avec un fond visuel Aika déjà préparé (`macos/scripts/dmg_background.png`).

```bash
./macos/scripts/build_dmg.sh
```

Cela produit `dist/Aika.dmg` (icône Aika, fond de fenêtre brandé, raccourci vers `/Applications`) et affiche son empreinte SHA-256.

Pour calculer l'empreinte séparément :
```bash
shasum -a 256 dist/Aika.dmg
```

## 7. Tests avant publication

Avant de publier, vérifiez au minimum :
- `open dist/Aika.dmg` → le DMG s'ouvre, affiche bien le fond et l'icône Aika, le glisser-déposer vers Applications fonctionne.
- L'app installée se lance sans avertissement Gatekeeper (`spctl -a -vvv` déjà validé à l'étape 5).
- L'icône est nette dans le Dock, le Finder et Launchpad (jeu d'icônes `AppIcon.appiconset` corrigé).
- Découverte réseau, QR Code, envoi/réception de fichiers avec au moins un autre appareil (Android/iOS/Windows/Linux) — voir la checklist de tests multi-appareils fournie séparément.

## 8. Publication GitHub Release

### Option A — manuelle
```bash
gh release create v1.0.0 \
  dist/Aika.dmg \
  --title "Aika 1.0.0" \
  --notes "Première version officielle d'Aika pour macOS."
```

### Option B — automatisée (GitHub Actions)

Un workflow prêt à l'emploi vous a été livré dans le chat sous le nom `macos_release.yml`. **Je n'ai pas pu l'écrire directement dans votre dépôt** : les fichiers sous `.github/workflows/` sont protégés en écriture à distance (mesure de sécurité empêchant une modification silencieuse de vos pipelines CI). Pour l'activer :

1. Copiez le fichier reçu dans le chat vers `.github/workflows/macos_release.yml` à la racine du dépôt (au même niveau que les workflows existants).
2. Dans GitHub → Settings → Secrets and variables → Actions, créez ces secrets (jamais commités, jamais vus par moi) :
   - `APPLE_CERTIFICATE_P12_BASE64` — export de votre certificat Developer ID Application (`.p12`, avec la clé privée) encodé en base64 (`base64 -i Certificate.p12 | pbcopy`).
   - `APPLE_CERTIFICATE_PASSWORD` — mot de passe utilisé à l'export du `.p12`.
   - `APPLE_TEAM_ID` — `MM9Z35FS2F`.
   - `APPLE_ID` — l'e-mail de votre identifiant Apple.
   - `APPLE_APP_SPECIFIC_PASSWORD` — le mot de passe généré à l'étape 2.2.
3. Poussez un tag `macos-v1.0.0` (préfixe volontairement distinct des tags des autres plateformes, pour ne pas déclencher leurs propres workflows) :
   ```bash
   git tag macos-v1.0.0
   git push origin macos-v1.0.0
   ```
4. Le workflow build, signe, notarise, crée le DMG et publie la Release GitHub automatiquement, sur un runner `macos-14` hébergé par GitHub.

## 9. Configuration minimale requise (à communiquer aux utilisateurs)

- macOS 11 (Big Sur) ou ultérieur — c'est la valeur configurée (`MACOSX_DEPLOYMENT_TARGET`) de façon cohérente dans le projet Xcode et le Podfile.
- Cette compatibilité n'a pas été testée sur une machine réelle en macOS 11 précisément — à valider avant de l'annoncer publiquement comme garantie.
