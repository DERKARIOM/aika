# Audit macOS — Aika 1.0.0

Date : 2 septembre 2026
Périmètre : `app/macos/`, configuration Flutter/Xcode associée, code Dart spécifique macOS.
Méthode : lecture directe du code source sur votre machine (bridge `device_bash`), sans exécution de build — voir la contrainte d'environnement plus bas.

---

## 0. Contrainte d'environnement à connaître avant tout

Le bridge qui me donne accès à vos fichiers (`device_bash`) tourne dans une **VM Linux isolée**, pas directement sur macOS. Concrètement, je n'ai accès ni à Xcode, ni à `flutter`/`dart`, ni à `codesign`, ni à `xcrun notarytool`, ni à `hdiutil` depuis cet environnement.

Conséquence sur les 20 points demandés :
- Tout ce qui est **audit statique** (lecture de code, de configuration, de plist, d'entitlements, cohérence de version, identité de marque) : je peux le faire moi-même, ce qui a été fait ci-dessous.
- Tout ce qui nécessite d'**exécuter** quelque chose (`flutter analyze`, `flutter build macos --release`, signature, notarisation, création du `.dmg`, tests réels de découverte réseau/QR/transfert entre appareils) : je ne peux pas le lancer moi-même. Je vais préparer les scripts, la configuration et une documentation pas-à-pas exacte, mais ces commandes devront être exécutées **par vous, sur votre Mac** (ou par un runner `macos-latest` en CI). Je vous donnerai exactement quoi taper, à chaque étape.

Ce n'est pas un blocage pour préparer la release — seulement pour l'exécuter physiquement.

---

## 1. Ce qui fonctionne déjà bien (bonne surprise)

Avant la liste des problèmes, un point important : la partie macOS n'est **pas** un simple fork brut de LocalSend. Elle a déjà été très largement travaillée et adaptée à Aika :

- `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER` (`com.naniger.aika`), copyright, `CFBundleDisplayName`, description caméra, App Groups (`naniger.aika.shared_group`) sont **déjà** en identité Aika — aucune trace de « LocalSend » visible utilisateur dans les fichiers macOS eux-mêmes.
- `AppDelegate.swift` est riche et propre à Aika : icône de menu bar avec couleur de marque (`#00645a`), `DockProgress` stylé, gestion « Lancer au démarrage », intégration au menu Services macOS (« Send to Aika »), ouverture directe des réglages Pare-feu macOS, gestion des bookmarks de sécurité (App Sandbox) pour les fichiers ouverts/glissés/partagés.
- Un **Share Extension** dédié existe (`macos/ShareExtension`), avec partage de données via App Group — fonctionnalité macOS avancée, déjà en place et déjà brandée Aika.
- Le Drag & Drop existe déjà, mais **seulement sur l'icône de la menu bar** (`ContentDropView`), pas encore sur la fenêtre principale (voir section 10 ci-dessous).
- App Sandbox est activé, `Hardened Runtime` est activé, un Team ID Apple Developer (`MM9Z35FS2F`) est déjà configuré dans le projet.
- La version (`1.0.0+1` dans `pubspec.yaml`) correspond déjà exactement à la cible « Aika 1.0.0 » demandée, et se propage correctement à `CFBundleShortVersionString`/`CFBundleVersion` via les variables Flutter (`FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER`) — rien à changer ici.
- Une page de licences open source existe déjà dans l'app (`about_page.dart` → lien Apache 2.0 + `LicensePage` Flutter listant les paquets tiers).

Le travail restant est donc plus proche d'une **finition professionnelle** que d'une refonte.

---

## 2. Problèmes identifiés, classés par criticité

### 🔴 Critique — icône de l'application mal configurée

`macos/Runner/Assets.xcassets/AppIcon.imageset/` est un **`.imageset` (image simple), pas un `.appiconset` (jeu d'icônes d'app)**. C'est le mauvais type d'asset Xcode pour une icône d'application macOS.

Détail vérifié :
- Le `Contents.json` ne déclare qu'une seule image (`logo_aika.png`, 2000×2000 px) pour l'échelle 1x ; les emplacements 2x et 3x sont **vides**.
- macOS a besoin d'un jeu complet aux tailles 16, 32, 128, 256, 512 pt (en 1x **et** 2x, soit 10 fichiers) pour un rendu net dans le Dock, le Finder, Launchpad et le sélecteur d'apps. Avec la configuration actuelle, Xcode génère un icône dégradé/incohérent selon les contextes, malgré l'image source haute résolution.
- Comparaison : `ios/Runner/Assets.xcassets/AppIcon.appiconset` existe et utilise le bon type — l'incohérence est spécifique à macOS.

C'est exactement le problème que vous pressentiez au point 11 de votre cahier des charges. **Correction nécessaire avant toute release.**

Par contraste, l'icône du Share Extension (`macos/ShareExtension/icon.icns`) est un vrai `.icns` multi-résolution bien formé (512@2x, 512, 256, 128) — celui-là est techniquement correct (à vérifier seulement qu'il affiche bien le logo Aika et non un reliquat).

### 🔴 Critique — signature de distribution non configurée

Toutes les configurations de build (`Debug`, `Release`, `Profile`, pour `Runner` **et** `ShareExtension`) utilisent :
```
CODE_SIGN_IDENTITY = "Apple Development"
CODE_SIGN_STYLE = Automatic
```
« Apple Development » sert à exécuter l'app sur votre propre Mac en développement/debug. Pour une **distribution directe hors Mac App Store** (ce que vous souhaitez), il faut un certificat **« Developer ID Application »**, associé à votre Team ID (`MM9Z35FS2F`, déjà présent). `Hardened Runtime` est heureusement déjà activé (`YES`), c'est un prérequis pour la notarisation.

Rien d'anormal à ce stade — c'est la configuration par défaut de `flutter create`. Mais il faut la faire évoluer avant de pouvoir signer/notariser une build de distribution. Je détaille la procédure exacte (manuelle, sur votre Mac / votre compte Apple Developer) dans le plan ci-dessous.

### 🟠 Important — restriction réseau multicast (App Sandbox)

La découverte automatique d'appareils Aika repose sur un **groupe multicast UDP configurable** (`multicastGroup`, visible dans `lib/provider/settings_provider.dart`, `lib/config/init.dart`, avec un avertissement utilisateur explicite si l'adresse est personnalisée). C'est un vrai multicast bas niveau, pas uniquement du Bonjour/`NSNetService`.

Depuis macOS Sonoma (14), **une app en App Sandbox qui utilise du multicast UDP brut nécessite l'entitlement restreint `com.apple.developer.networking.multicast`**, à demander explicitement à Apple (formulaire dédié, avec justification, délai d'approbation — ce n'est pas automatique comme les autres entitlements). Or :
- L'app est bien en App Sandbox (`com.apple.security.app-sandbox = true`).
- Cet entitlement **n'est présent ni dans `Release.entitlements` ni dans `DebugProfile.entitlements`**.

Le `Info.plist` déclare bien des services Bonjour (`NSBonjourServices` : `_http._tcp`, `_bonjour._tcp`, `_lnp._tcp.`), ce qui suggère qu'il existe peut-être un mécanisme de repli via Bonjour standard (qui, lui, ne nécessite pas cet entitlement). Mais je ne peux pas exécuter l'app pour vérifier lequel des deux chemins (multicast brut vs Bonjour) est réellement utilisé au runtime, ni si l'un des deux suffit à assurer une découverte fiable.

**Risque concret :** sur un Mac récent (Sonoma/Sequoia), la découverte automatique d'autres appareils Aika pourrait ne pas fonctionner de façon fiable tant que cet entitlement n'est pas obtenu — avec la fonctionnalité QR Code comme solution de secours (qui, elle, ne dépend pas du multicast).

### 🟡 Mineur — Drag & Drop limité à la menu bar

Le point 10 de votre cahier des charges demande une amélioration du Drag & Drop (glisser un fichier depuis le Finder). Actuellement, cette fonctionnalité **existe déjà**, mais uniquement sur l'icône de la barre de menu (`ContentDropView` attaché au `NSStatusItem`). Rien ne semble équivalent sur la fenêtre principale de l'app elle-même — à confirmer en testant l'app, mais le code Swift macOS ne montre pas de second point d'ancrage pour le drag & drop en dehors de la menu bar.

### 🟡 Mineur — workflows GitHub existants sans volet macOS

Le dépôt (`aika/.github/workflows/`, à la racine du repo — `app/` et `aika_site_web/` sont deux dossiers du même repo Git) contient des workflows hérités de LocalSend (`compile_apk.yml`, `linux_build.yml`, `winget.yml`, `compile_arm64_appimage.yml`, `test_rpm.yml`, etc.) mais **aucun pour macOS**. Ce sont des artefacts de l'upstream LocalSend, pas quelque chose que je vais modifier (vous m'avez demandé de ne pas toucher aux autres plateformes) — je vais simplement en ajouter un nouveau, dédié macOS, sans toucher aux existants.

### 🟡 Mineur / informatif — nom de paquet interne `rust_lib_localsend_app`

Un plugin Flutter natif (Rust, visible dans `macos/Pods/Target Support Files/rust_lib_localsend_app/`) garde le nom interne `rust_lib_localsend_app`. C'est un identifiant technique **invisible pour l'utilisateur final** (pas de branding, pas de mention légale) — le renommer serait un refactor risqué pour un bénéfice purement cosmétique en interne. Je recommande de **ne pas y toucher**, sauf si vous y tenez pour des raisons de principe.

### 🟢 À vérifier plutôt qu'à corriger — `LSUIElement = true`

`Info.plist` déclare `LSUIElement = true`, combiné à `BDW_HIDE_ON_STARTUP` et `hiddenWindowAtLaunch()` côté Swift : Aika est conçue comme une **app de menu bar qui démarre masquée**, cohérent avec le `NSStatusItem` mis en place dans `AppDelegate.swift`. C'est un choix d'architecture assumé, pas un bug. Le point à vérifier **en testant réellement sur un Mac** : est-ce que l'icône apparaît bien dans le Dock quand la fenêtre principale est affichée (Cmd+Tab, etc.), ou est-ce que l'app reste complètement invisible du Dock même fenêtre ouverte ? Aucun appel à `NSApp.setActivationPolicy` n'a été trouvé dans le code Swift du projet — je ne peux pas conclure sans un test réel.

---

## 3. Compatibilité macOS

- `MACOSX_DEPLOYMENT_TARGET = 11.0` (Big Sur) est fixé de façon cohérente dans le projet Xcode **et** dans `macos/Podfile` (`platform :osx, '11.0'` + forcé à `11.0` pour tous les Pods en post-install). C'est cohérent, pas de conflit détecté.
- Big Sur (2020) comme plancher est raisonnable pour une app moderne écrite avec des plugins Flutter récents (`window_manager`, `bitsdojo_window_macos`, `mobile_scanner`, etc.).
- Je ne peux **pas** garantir que chaque plugin fonctionne réellement à partir de macOS 11 sans un test sur une machine réelle avec cette version — je ne vais pas annoncer une compatibilité que je n'ai pas testée. Ce point reste à valider dans votre checklist de tests (section 18 de votre cahier des charges).

---

## 4. Bundle Identifier — recommandation

Vous m'avez demandé de ne pas choisir arbitrairement et d'analyser d'abord. Conclusion : **`com.naniger.aika` est déjà en place, et je recommande de le garder tel quel**, pour ces raisons factuelles :
- Il suit la convention Apple standard (reverse-DNS basé sur votre domaine `naniger.com`, déjà utilisé partout ailleurs dans le projet : site web, URLs dans l'app).
- Il est **déjà propagé de façon cohérente** dans plusieurs endroits interdépendants : `PRODUCT_BUNDLE_IDENTIFIER` du Runner, `com.naniger.aika.ShareExtension` pour l'extension, le groupe App Group `naniger.aika.shared_group`, référencé à la fois dans `Release.entitlements`, `DebugProfile.entitlements` et `ShareExtension.entitlements`.
- Le changer maintenant casserait ces associations (App Group, futur profil de provisioning, éventuelle future configuration Apple Developer Portal) sans aucun bénéfice pratique.

Je considère ce point comme déjà réglé, sauf si vous avez une raison spécifique d'en vouloir un autre.

---

## 5. Signature, notarisation, distribution directe — ce qu'il faudra faire (sur votre Mac)

Rien de ceci n'est fait automatiquement par moi — voici la feuille de route que je documenterai en détail (`docs/macos-release.md`, point 19) une fois les corrections de code validées :

1. Dans votre compte Apple Developer (déjà associé au Team `MM9Z35FS2F`), générer un certificat **« Developer ID Application »** (Xcode peut le faire automatiquement si votre compte a les droits, ou via developer.apple.com → Certificates).
2. Passer `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE` en configuration adaptée à la distribution pour les schémas de build Release (je proposerai le diff exact).
3. Build : `flutter build macos --release` (à exécuter par vous ou en CI macOS).
4. Signature de `Aika.app` avec `codesign`, options `--options runtime` (Hardened Runtime, déjà activé côté entitlements).
5. Notarisation via `xcrun notarytool submit ... --wait`, puis `xcrun stapler staple Aika.app`.
6. Vérification Gatekeeper : `spctl -a -vvv Aika.app`.

Je ne vous demanderai jamais vos identifiants Apple, mots de passe d'application, ou certificats — je vous donnerai les commandes exactes à exécuter vous-même, avec les identifiants d'App Store Connect / Apple Developer que vous seul possédez.

---

## 6. Plan de migration proposé — Aika 1.0.0 macOS

Dans l'ordre, si vous validez :

1. **Corriger l'icône de l'app** : recréer `AppIcon.appiconset` avec les 10 tailles requises générées à partir du logo Aika officiel (déjà utilisé pour le Play Store), remplacer l'`.imageset` cassé. Vérifier au passage que `AppIconWithSuccessMark`/`AppIconWithErrorMark` (badges de statut du Dock) et le `StatusBarItemIcon` restent cohérents visuellement.
2. **Ajouter le Drag & Drop sur la fenêtre principale** (pas seulement la menu bar), en réutilisant le même mécanisme (`registerForDraggedTypes`) déjà éprouvé dans `ContentDropView.swift`.
3. **Documenter/traiter le point multicast** : soit initier la demande d'entitlement `com.apple.developer.networking.multicast` auprès d'Apple (délai indépendant de moi), soit confirmer/renforcer un repli Bonjour fonctionnel — après vérification sur votre Mac réel.
4. **Préparer la configuration de signature Developer ID** (fichiers de config Xcode ajustés, sans jamais toucher à vos certificats).
5. **Créer le script/pipeline DMG** professionnel (nom, icône, raccourci vers `/Applications`).
6. **Ajouter un workflow GitHub Actions macOS** (`macos-latest`), déclenché sur tag `v1.0.0`, avec les secrets **documentés mais non créés** par moi.
7. **Rédiger `docs/macos-release.md`** avec toute la procédure (prérequis, build, signature, notarisation, DMG, tests, publication).
8. **Vous fournir la checklist de tests multi-appareils** (section 18) à exécuter vous-même, puisque je n'ai pas accès à un second appareil physique pour tester la découverte réseau réelle.

Aucune de ces étapes ne touche `android/`, `ios/`, `windows/`, `linux/`, ni le site web.

---

## 7. Ce qu'il me manque pour aller plus loin

- Confirmation que vous voulez que je procède dans cet ordre (ou une autre priorité).
- Préférence d'outil pour le DMG (voir ma question ci-dessous).
- Accès à un Mac réel (le vôtre) pour que vous exécutiez les commandes de build/signature/notarisation/tests que je ne peux pas lancer moi-même depuis cet environnement.
