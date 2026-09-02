# Audit & étude de faisabilité — « Partager Aika » (envoi de l'APK via Bluetooth)

Statut : **audit uniquement, aucun code écrit ni modifié**, conformément à la demande.
Date : 2026-09-02.

## 1. Ce qui existe déjà dans Aika

- **Aucun plugin ni code Bluetooth** dans le projet (`pubspec.yaml` grepé : `connectivity_plus`,
  `device_info_plus`, `network_info_plus`, `open_filex`, `package_info_plus`, `permission_handler`,
  `share_handler`, `shared_preferences` — rien de Bluetooth).
- **Découverte et transfert actuels** (`lib/provider/network/*`) : `nearby_devices_provider.dart`,
  `scan_facade.dart`, `server_provider.dart`, `receive_controller.dart`, `webrtc/signaling_provider.dart`.
  C'est le mécanisme LocalSend classique : multicast UDP + serveur HTTP sur le réseau local, plus un
  canal WebRTC pour la signalisation. **Tout ceci est fondé sur IP/réseau local — rien n'est réutilisable
  tel quel pour du Bluetooth**, qui est un transport radio complètement différent (pairing, sockets RFCOMM,
  pas d'adresse IP). Conformément à la consigne de ne pas forcer le protocole existant, ce module n'est
  **pas** la bonne base pour cette fonctionnalité.
- **Récupération et empaquetage d'un APK installé** : déjà résolu par l'existant.
  - `lib/provider/apk_provider.dart` utilise `DeviceApps.getInstalledApplications(...)` (plugin
    `device_apps`, fork Git épinglé sur un commit précis dans `pubspec.yaml` via
    `dependency_overrides`) pour lister toutes les apps installées (fonctionnalité « APK Picker »,
    `lib/pages/apk_picker_page.dart`).
  - `lib/util/native/cross_file_converters.dart` → `CrossFileConverters.convertApplication(Application app)`
    transforme déjà un objet `Application` en `CrossFile` prêt à être envoyé, avec un nom généré
    dynamiquement (`'${app.appName} - v${app.versionName}.apk'`) — exactement ce que demande la section 6
    (pas de chemin en dur).
  - **Nuance importante sur les permissions** : `getInstalledApplications` énumère TOUTES les apps, ce qui
    nécessite `QUERY_ALL_PACKAGES` (déjà déclarée dans le manifest, utilisée par le picker existant). Pour
    « Partager Aika », on n'a besoin QUE des infos d'Aika elle-même — une auto-consultation d'un package par
    lui-même ne nécessite PAS `QUERY_ALL_PACKAGES` côté Android (l'auto-visibilité est toujours accordée).
    Il faut donc éviter de réutiliser l'énumération globale et privilégier un accès ciblé à l'app elle-même
    (voir section 4).
- **Ouverture/installation d'un fichier .apk reçu** : déjà géré. `lib/util/native/open_file.dart` détecte
  explicitement `FileType.apk` sur Android et route vers `OpenFilex.open(filePath)`
  (package `open_filex`), ce qui déclenche l'installateur système Android. La permission
  `REQUEST_INSTALL_PACKAGES` est déjà déclarée dans `AndroidManifest.xml`.
- **`share_handler`** : confirmé utilisé uniquement pour la RÉCEPTION (une autre app qui partage un
  fichier VERS Aika via l'intent Android `SEND`). Il n'existe aujourd'hui **aucun mécanisme d'envoi
  sortant** (Aika qui partage un fichier vers une autre app / le système).
- **Canal natif existant** : `lib/util/native/channel/android_channel.dart` est un platform channel
  Android déjà en place et déjà utilisé pour des besoins spécifiques (ex. tuile rapide). C'est le point
  d'extension naturel si un petit bout de code natif Kotlin est nécessaire, plutôt que d'ajouter un
  nouveau plugin tiers.

## 2. Configuration Android actuelle (manifest / Gradle)

- `compileSdkVersion 36`, `targetSdkVersion 36` (Android 16), `applicationId "com.naniger.aika"`.
- `minSdkVersion` : hérité de `flutter.minSdkVersion` (pas de valeur en dur) ; les métadonnées du dernier
  build release indiquent `minSdkVersionForDexing: 24` (Android 7.0) — donc les versions couvertes vont
  d'Android 7 à Android 16, avec Android 12+ (API 31+) comme le vrai point de bascule pour tout ce qui
  concerne le Bluetooth (nouveau modèle de permissions runtime).
- Permissions Bluetooth : **aucune** actuellement déclarée (`BLUETOOTH`, `BLUETOOTH_ADMIN`,
  `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` : absentes).
- Aucune balise `<queries>` (visibilité de packages Android 11+) n'est déclarée.
- **Aucun `FileProvider` n'est configuré** dans le projet (ni `<provider>` dans le manifest, ni
  `res/xml/file_paths.xml`). C'est un point à ajouter quelle que soit l'option retenue ci-dessous, car
  partager un fichier vers une autre app exige une URI `content://`, pas un chemin de fichier brut
  (bloqué par Android depuis l'API 24 - `FileUriExposedException`).
- `REQUEST_INSTALL_PACKAGES` et `QUERY_ALL_PACKAGES` sont déjà présentes (héritées du picker existant).

## 3. Le plugin `device_apps` (fork épinglé)

Le projet utilise un fork Git (`Tienisto/device_apps`, commit épinglé), avec un commentaire existant dans
le `pubspec.yaml` signalant que ce package devrait être migré à terme. Cette VM de développement distante
n'a pas de cache Dart/pub, donc son code source exact n'a pas pu être inspecté directement ici ; il faudra
vérifier dans le code du plugin (ou son historique GitHub) s'il expose une méthode de consultation d'une
SEULE app par nom de package (type `getApp('com.naniger.aika')`), ce qui est l'API attendue pour ce genre
de plugin et éviterait tout recours à l'énumération globale.

**Dans tous les cas, il existe une solution de repli fiable** : même si le plugin ne propose pas cette
méthode, une auto-consultation de l'app par elle-même peut se faire par un tout petit ajout natif Kotlin
dans `android_channel.dart` (`context.packageManager.getPackageInfo(context.packageName, 0)`), qui ne
nécessite aucune permission Android particulière. Ce point ne bloque donc pas la faisabilité, seulement
le choix d'implémentation (à trancher à l'implémentation, pas maintenant).

## 4. Bluetooth Classic vs BLE vs Sharesheet — étude comparative

- **BLE (Bluetooth Low Energy)** : débit trop faible pour un APK de plusieurs dizaines de Mo — écarté
  d'emblée, ce n'est pas fait pour transférer des fichiers de cette taille.
- **Bluetooth Classic (RFCOMM / `BluetoothSocket`, SPP)** : seule option de transport Bluetooth
  techniquement viable en volume, mais :
  - Aucun plugin Flutter maintenu n'existe aujourd'hui pour ça (`flutter_bluetooth_serial` est abandonné) ;
    il faudrait écrire une implémentation Android native complète (Kotlin), avec tout le cycle
    scan → appairage → connexion → envoi par sockets.
  - Il faudrait ajouter et gérer tout le nouveau modèle de permissions Android 12+
    (`BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` / `BLUETOOTH_ADVERTISE`) ET l'ancien modèle pour les
    versions antérieures (`BLUETOOTH` / `BLUETOOTH_ADMIN` / `ACCESS_FINE_LOCATION`) — un chantier de
    permissions conséquent à lui seul, à tester sur 5 versions majeures d'Android.
  - **Problème structurel rédhibitoire, propre à ce cas d'usage précis** : le destinataire n'a PAS Aika
    installée — c'est justement tout l'objectif de la fonctionnalité. Un protocole Bluetooth qu'Aika
    inventerait elle-même ne serait compris que par... une autre instance d'Aika. Or il n'y a, par
    définition, aucune instance d'Aika qui tourne sur le téléphone du destinataire pour accepter cette
    connexion RFCOMM personnalisée. Donc une gestion Bluetooth directe par Aika n'est pas seulement plus
    complexe : **elle est structurellement incapable d'atteindre l'objectif** dans ce scénario précis
    (destinataire sans Aika). Ce serait viable pour un transfert Aika-vers-Aika (les deux appareils ont déjà
    l'app), mais ce n'est pas le cas d'usage demandé ici.

- **Sharesheet Android (`Intent.ACTION_SEND`) — laisser Android gérer le Bluetooth** : Aika prépare le
  fichier (APK d'Aika elle-même) et le fichier via l'intent standard de partage Android, avec le type MIME
  `application/vnd.android.package-archive`. Android affiche alors son sélecteur de partage natif, qui
  propose les apps compatibles installées sur l'appareil de l'utilisateur (le partage Bluetooth intégré
  d'Android — "Bluetooth"/"Partage à proximité" selon les fabricants/versions —, Nearby Share/Quick Share,
  etc.). C'est le récepteur Bluetooth **du système Android lui-même** qui reçoit le fichier côté
  destinataire — ce récepteur existe de façon standard sur tout téléphone Android, qu'Aika y soit
  installée ou non. C'est donc la seule approche qui fonctionne réellement pour ce cas d'usage précis.

## 5. Comparaison Option A / Option B (demandée avant tout choix)

| | **Option A** — Aika gère le Bluetooth elle-même | **Option B** — Aika délègue au Sharesheet Android |
|---|---|---|
| Fonctionne pour un destinataire sans Aika | **Non** (aucune app en face pour parler le protocole) | **Oui** (le récepteur est le système Android lui-même) |
| Nouvelles permissions à demander | Beaucoup (BLUETOOTH_SCAN/CONNECT/ADVERTISE + legacy) | Aucune permission Bluetooth (Aika ne touche jamais la pile Bluetooth) |
| Nouveau code natif | Important (implémentation RFCOMM complète, aucun plugin maintenu) | Minime (un intent standard + un `FileProvider`) |
| Fiabilité / maintenance | Faible (à maintenir seul, sur 5 versions d'Android) | Élevée (utilise des API Android stables et documentées) |
| Repli automatique si Bluetooth indisponible (section 10) | À coder soi-même | Automatique : le sélecteur Android propose ce qui est réellement disponible (Bluetooth, Quick Share, etc.) |
| Contrôle fin de l'UI pendant le transfert (progression, vitesse, ETA) | Total (c'est Aika qui gère le socket) | Limité : une fois l'intent lancé, le transfert Bluetooth lui-même se déroule dans l'app système, hors de l'UI d'Aika |
| Respect du modèle de sécurité Android | Risqué (réinvente une pile de sécurité/permissions) | Natif (s'appuie entièrement sur les mécanismes déjà validés par Android) |

**Recommandation : Option B.** L'option A n'est pas simplement plus complexe — elle est incapable
d'atteindre l'objectif réel de la fonctionnalité (envoyer Aika à un appareil qui ne l'a pas encore), alors
que l'option B fonctionne précisément parce qu'elle s'appuie sur un récepteur Bluetooth qui existe déjà,
nativement, sur tous les téléphones Android.

## 6. Point tranché : écran post-réception (section 5 du cahier des charges)

Le cahier des charges décrit, après réception : *« Aika a été reçu avec succès. » → [ Installer Aika ]*.
Cet écran suppose qu'un minimum de code Aika s'exécute côté destinataire pour l'afficher. Or, dans le vrai
cas visé (destinataire sans Aika), aucun code Aika ne tourne sur cet appareil au moment de la réception —
c'est le système Android (Bluetooth/Partage à proximité) qui reçoit le fichier et affiche sa propre
notification générique (« Fichier reçu, appuyez pour ouvrir »), puis l'installateur de paquets Android
standard s'ouvre quand l'utilisateur appuie dessus.

**Décision validée par l'utilisateur (2026-09-02) : on accepte l'UI générique d'Android pour cette étape.**
Aika ne tente pas d'afficher un écran personnalisé « Aika reçu / Installer » pour un destinataire qui ne
l'a pas encore — ce serait techniquement impossible et malhonnête à prétendre. L'expérience Aika
personnalisée se limite donc au côté ENVOI (écran « Partager Aika », confirmation avant envoi) ; côté
réception pour un nouvel utilisateur, l'expérience standard d'Android (notification + installateur système)
prend le relais, exactement comme pour n'importe quel fichier partagé par Bluetooth aujourd'hui.

## 7. Architecture recommandée (résumé, sans code)

- Fichiers concernés (nouveaux) : un petit provider de résolution de l'APK d'Aika elle-même (auto-lookup,
  pas d'énumération globale) ; réutilisation telle quelle de `CrossFileConverters.convertApplication` pour
  générer un nom de fichier dynamique ; un nouvel écran « Partager Aika » (icône + description, confirmation
  avant envoi, déclenchement du partage) ; ajout d'un `FileProvider` (fichier `res/xml/file_paths.xml` +
  déclaration dans le manifest) — actuellement absent du projet et nécessaire quel que soit le choix
  d'implémentation.
- Dépendance potentielle : soit le paquet `share_plus` (bien maintenu, fait exactement ce qu'il faut pour
  déclencher un `ACTION_SEND`), soit une petite extension du canal natif existant
  `android_channel.dart` — un choix d'implémentation à faire plus tard, sans impact sur la faisabilité.
- API Android utilisées : `Intent.ACTION_SEND` / `Intent.createChooser`, `androidx.core.content.FileProvider`,
  et un accès ciblé à `PackageManager` pour les infos de l'app elle-même (nom, version, taille, chemin de
  l'APK).
- Permissions nécessaires : aucune permission Bluetooth nouvelle ; uniquement l'ajout du `FileProvider`
  dans le manifest (déclaration, pas une permission runtime). `REQUEST_INSTALL_PACKAGES` déjà présente
  reste utile pour la partie « ouvrir/installer » du côté d'un appareil qui a déjà Aika.
- Limitations par version d'Android : aucune limitation spécifique identifiée entre Android 12 et 16 pour
  cette approche (le Sharesheet et `FileProvider` sont stables sur toute cette plage) ; la vraie variable
  n'est pas la version d'Android mais la disponibilité du Bluetooth/Partage à proximité sur l'appareil, ce
  qui est justement géré automatiquement par le sélecteur système (section 10).

## 8. Réponse directe à la question posée

Un transfert Bluetooth **directement piloté par le code d'Aika**, vers un appareil qui n'a pas encore Aika,
**n'est pas réalisable** — non pas à cause d'une restriction Android côté envoi, mais parce qu'il n'existe
aucune instance d'Aika côté réception pour comprendre un protocole propriétaire. En revanche, un transfert
**via Bluetooth (ou Partage à proximité) est bien possible et réalisable avec les API Android officiellement
supportées**, en laissant Android lui-même gérer le Bluetooth via son mécanisme de partage standard
(Sharesheet) — c'est la seule architecture qui réponde réellement à l'objectif, et c'est celle recommandée
ci-dessus (Option B).

---
*Aucune ligne de code n'a été écrite ou modifiée pour cette fonctionnalité. Cet audit attend une décision
de l'utilisateur avant toute implémentation.*

## 9. Implémentation réalisée (2026-09-02)

Suite à la validation de l'architecture (Option B) et de la décision de la section 6, le code a été
écrit :

- `android/app/src/main/AndroidManifest.xml` : déclaration du `FileProvider` (`androidx.core.content.FileProvider`),
  `exported="false"`, autorité `${applicationId}.fileprovider`.
- `android/app/src/main/res/xml/file_paths.xml` (nouveau) : `<root-path>` nécessaire car l'APK installé
  d'Aika vit hors des répertoires privés habituels de l'app.
- `android/app/src/main/kotlin/com/naniger/aika/MainActivity.kt` : nouvelle méthode native `shareOwnApk`
  sur le canal existant `com.naniger.aika/localsend` — résout dynamiquement le nom, la version et le
  chemin de l'APK d'Aika elle-même via `PackageManager` (auto-consultation, aucune permission
  supplémentaire), construit l'URI `content://` via le `FileProvider`, puis lance
  `Intent.ACTION_SEND` + `Intent.createChooser` (le Sharesheet natif d'Android).
- `lib/util/native/channel/android_channel.dart` : `shareOwnApkAndroid()` + `OwnApkShareResult`, le
  wrapper Dart de cette méthode.
- `lib/pages/share_aika_page.dart` (nouveau) : écran « Partager Aika » (logo, description, bouton de
  partage, dialogue de confirmation avant envoi, états préparation/succès/erreur), clair sur le fait que
  c'est Android qui prend le relais pour le choix du moyen de transport.
- `lib/pages/tabs/settings_tab.dart` : nouvelle entrée « Partager Aika » dans la section « Autre »,
  visible uniquement sur Android (`checkPlatform([TargetPlatform.android])`).
- `assets/i18n/en.json` / `assets/i18n/fr.json` : nouvelles chaînes (`settingsTab.other.shareAika`,
  section `shareAikaPage`). Les autres langues retombent automatiquement sur l'anglais
  (`fallback_strategy: base_locale` déjà configuré dans `build.yaml`).

**Aucune nouvelle dépendance tierce ajoutée** (pas de `share_plus`) : tout repose sur le canal natif déjà
existant dans le projet, pour éviter de dépendre d'une version de package que cet environnement ne peut
pas vérifier (pas d'accès à pub.dev depuis cette machine de développement à distance).

**Étapes à faire toi-même avant de builder** (cet environnement n'a pas Flutter/Dart) :
1. `dart run slang` (ou ta commande habituelle de génération i18n) pour régénérer
   `lib/gen/strings*.g.dart` à partir des nouveaux `en.json`/`fr.json` — sans ça, `t.shareAikaPage.*` ne
   compilera pas.
2. `flutter pub get` (par précaution, aucune dépendance n'a changé mais ça ne coûte rien).
3. `flutter build apk` (ou lancer sur un appareil/émulateur Android) et tester le flux complet.

**Tests à faire à la main** (parmi les 14+ demandés en section 14 du cahier des charges) : sur un
appareil réel avec Bluetooth activé (le chooser doit proposer Bluetooth/Partage à proximité/etc.),
Bluetooth désactivé (le chooser doit tout de même s'ouvrir avec les autres apps disponibles — comportement
géré entièrement par Android, pas par ce code), annulation depuis le dialogue de confirmation, annulation
depuis le chooser système lui-même, et vérification sur Android 12/13/14/15/16 si possible.
