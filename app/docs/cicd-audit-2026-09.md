# Audit CI/CD GitHub Actions — release desktop Aika (Linux/Windows/macOS)

Statut : **audit uniquement, aucun workflow ni script créé**, conformément à la méthode demandée.
Date : 2026-09-03.

## 1. Ce qui existe déjà (bonne surprise : une bonne partie du travail est amorcée)

- **`pubspec.yaml`** : `version: 1.0.1+2`, `environment: { flutter: ^3.41.0, sdk: ^3.11.0 }`. Aucun `.fvmrc`
  ni `fvm_config.json` — pas de version Flutter épinglée de façon déterministe pour l'instant.
- **Plateformes desktop déjà scaffoldées** : `android/`, `ios/`, `linux/`, `macos/`, `windows/` sont tous
  présents (générés via `flutter create`), mais **Linux et Windows n'ont jamais été buildés ni testés** à
  ce jour (seul macOS a un historique de build réussi, documenté dans `docs/macos-release.md`).
- **Tests unitaires réels existent** : `test/unit/**` (provider, util, model, i18n) — `flutter test` a donc
  un contenu réel à exécuter, pas une coquille vide.
- **macOS — packaging déjà écrit et fonctionnel** : `macos/scripts/build_dmg.sh` (utilise `create-dmg`,
  fond `dmg_background.png` déjà brandé Aika, calcule le SHA-256 en sortie) — documenté et déjà utilisé
  manuellement d'après `docs/macos-release.md`. Directement réutilisable en CI.
- **Linux — packaging déjà à moitié configuré** : `linux/packaging/deb/make_config.yaml` et
  `linux/packaging/rpm/make_config.yaml` existent, **déjà personnalisés pour Aika** (maintainer, email,
  icône, dépendances système pour le tray `libappindicator`/`libayatana`, catégories, mots-clés). Ce
  format de fichier est celui de l'outil **`flutter_distributor`** (`dart pub global activate
  flutter_distributor`). **Cependant, le fichier racine `distribute_options.yaml`, que
  `flutter_distributor` exige pour orchestrer un build, est absent** — la config est prête mais jamais
  câblée ni testée de bout en bout.
- **Windows — MSIX amorcé mais bloqué** : `windows/aika.exe.manifest` existe déjà avec un commentaire
  explicite laissé par une session précédente : le `publisher` du manifeste MSIX est encore celui du
  certificat Microsoft Store de LocalSend (l'auteur amont), **pas un certificat Aika** — packaging/signature
  ne fonctionneront pas tant qu'un vrai certificat Aika n'existe pas. `windows/install_msix_helper.ps1`
  (script d'installation locale du `.msix`) existe aussi. **Aucun `distribute_options.yaml` ni certificat
  Windows n'existe** — cette piste est à l'arrêt exactement pour la même raison que le blocage Apple
  Developer déjà rencontré sur macOS (signature payante requise).

## 2. Compatibilité des dépendances par plateforme

`pubspec.yaml` contient déjà plusieurs commentaires très utiles laissés par les développeurs précédents,
qui confirment que la compatibilité desktop a déjà été réfléchie :
- `drift_flutter` : explicitement commenté "Cross-platform (Android/iOS/macOS/Windows/Linux)".
- `mobile_scanner` : commenté "Aucun plugin maintenu ne supporte le scan live sur Windows/Linux" — géré
  par un garde-fou existant, `checkPlatformHasLiveQrScanner()`, et compensé par `zxing2` (scan d'un QR
  depuis une image, pur Dart, fonctionne partout).
- `permission_handler_windows` : **déjà remplacé par un override "noop"** ("cause des problèmes sur
  Windows 7"), signe que Windows a déjà été anticipé au niveau des permissions.
- `gal` (sauvegarde galerie), `device_apps` (Android uniquement), `share_handler`, `in_app_purchase`,
  `wechat_assets_picker`, `image_picker` : tous mobile-only ou partiellement mobile-only. Le code utilise
  déjà des garde-fous (`checkPlatformWithGallery()`, `checkPlatform([...])`) à plusieurs endroits — mais
  ce n'est **pas vérifié exhaustivement** pour chaque appel ; un premier build Linux/Windows réel est le
  seul moyen de confirmer qu'aucun de ces plugins ne casse la compilation (le risque le plus probable
  serait `in_app_purchase`, qui n'a pas d'implémentation Windows/Linux connue — mais comme il s'agit d'un
  plugin fédéré, l'absence d'implémentation pour une plateforme donnée ne bloque normalement PAS la
  compilation, seulement l'usage runtime à cet endroit précis).
- **Héritage LocalSend** : Aika est un fork de LocalSend, qui publie lui-même officiellement des builds
  Linux/Windows/macOS en amont — la quasi-totalité des dépendances desktop (`bitsdojo_window`,
  `window_manager`, `tray_manager`, `screen_retriever`, `desktop_drop`, `pasteboard`, `win32_registry`,
  `windows_taskbar`, `yaru`, `dynamic_color`) proviennent de cette base déjà éprouvée en desktop. Le risque
  réel se concentre sur les dépendances ajoutées spécifiquement pour Aika (mobile-first : `device_apps`,
  `gal`, `mobile_scanner`, `wechat_assets_picker`, `image_picker`, `in_app_purchase`).

**Conclusion** : rien d'identifié à ce stade qui empêcherait structurellement la compilation Linux/Windows,
mais **ni l'un ni l'autre n'a jamais été réellement testé** — le premier run de la pipeline CI sera donc
aussi le premier vrai test de compatibilité de ces plateformes pour Aika.

## 3. Runners GitHub Actions — vérification (pas une supposition)

- **`macos-latest` est désormais un runner Apple Silicon (arm64) exclusivement** — Apple/GitHub ont retiré
  les images Intel (macOS 13 fermée depuis septembre 2025). Un build "x64" pur n'est donc plus produit "en
  passant" sur ce runner.
- **Vérification concrète sur le projet** : `macos/Runner.xcodeproj/project.pbxproj` ne force
  `ONLY_ACTIVE_ARCH = YES` **que sur la configuration Debug** (une seule occurrence dans tout le fichier,
  confirmée juste avant `name = Debug;`). La configuration Release ne restreint pas `ARCHS` — elle utilise
  donc le comportement standard Xcode/Flutter, qui construit un **binaire universel (arm64 + x86_64)**
  même en exécutant le build sur un runner arm64. **Conclusion : le DMG produit sera bien universel**, pas
  arm64-only ni x64-only — mais ça sera vérifié explicitement en CI via `lipo -info` sur le binaire avant
  de packager le DMG (plutôt que supposé). Le nom de fichier doit donc être
  `Aika-vX.Y.Z-macos-universal.dmg`, pas `-macos-x64.dmg` comme dans l'exemple initial.
- `ubuntu-latest` / `windows-latest` : pas de piège équivalent identifié, ce sont des runners x86_64
  standards.

## 4. Version Flutter à épingler

Pas de `.fvmrc` existant. Pour garantir que la CI utilise **exactement** la version Flutter déjà prouvée
fonctionnelle sur macOS en local (celle qui a produit le build réussi documenté dans
`docs/macos-release.md`), la version exacte doit venir de `flutter --version` exécuté sur ta machine —
plutôt que de deviner une version "récente" compatible avec `^3.41.0`, ce qui risquerait d'introduire un
comportement différent de ce qui a déjà été testé.

## 5. Décisions à trancher avant l'implémentation

### Décision A — Windows : que fait-on du MSIX déjà amorcé ?
Le MSIX non signé **ne s'installe pas** par un simple double-clic (contrairement à un `.exe` non signé,
qui s'installe avec juste un avertissement SmartScreen contournable — le même genre de friction que
Gatekeeper sur macOS, mais qui n'empêche pas l'installation). Continuer le MSIX nécessiterait un
certificat de signature de code Windows (payant, comparable au blocage Apple Developer déjà rencontré).
Deux options :
- **Option recommandée** : produire un installateur **Inno Setup non signé** (`Aika-vX.Y.Z-windows-x64-setup.exe`)
  — crée des raccourcis, gère la désinstallation proprement, aucun certificat requis pour l'instant. Le
  MSIX déjà scaffoldé reste en place pour plus tard (une fois un certificat disponible), sans être supprimé.
- **Option alternative** : produire un simple exécutable portable zippé (`Aika-vX.Y.Z-windows-x64.zip`),
  encore plus simple mais sans vraie installation/désinstallation/raccourcis.

### Décision B — Linux : `.deb` uniquement (comme demandé), ou aussi `.rpm` puisque déjà configuré ?
Le fichier `linux/packaging/rpm/make_config.yaml` existe déjà et est tout aussi prêt que celui du `.deb`.
Je propose de rester sur `.deb` uniquement pour cette première pipeline (comme demandé explicitement), et
de garder le RPM en option facilement activable plus tard (un seul job de plus dans la matrice).

## 6. Plan de pipeline proposé

```
Tag v*.*.* poussé
        │
        ▼
   job: validate  (vérifie le format du tag + cohérence avec pubspec.yaml, échoue sinon)
        │
   ┌────┼────────────┬───────────────┐
   │                 │               │
   ▼                 ▼               ▼
build-linux      build-windows   build-macos
(ubuntu-latest)  (windows-latest) (macos-latest)
   │                 │               │
flutter_distributor  Inno Setup   flutter build macos --release
  → .deb             → .exe        + lipo -info (vérif. universal)
                                    + macos/scripts/build_dmg.sh
   │                 │               │
   └────────┬────────┴───────────────┘
            ▼
      job: checksums (télécharge les 3 artifacts, calcule SHA256SUMS.txt)
            ▼
      job: publish-release (crée la GitHub Release, joint les 4 fichiers,
                             génère les notes de release)
```

Fichiers à créer à l'étape suivante (après validation de ce plan) :
- `.github/workflows/release.yml`
- `distribute_options.yaml` (racine — manquant, requis par flutter_distributor)
- `windows/installer/aika.iss` (script Inno Setup, si Décision A = installateur)
- `docs/github-actions-release.md` (documentation utilisateur finale)
- Mise à jour du `README.md` (section Releases)

Rien de ce qui précède n'a encore été créé — cette liste attend ta confirmation, notamment sur les
Décisions A et B ci-dessus, et le résultat de `flutter --version` sur ta machine.
