# Mises à jour intégrées (Google Play In-App Updates) — Android

Date : septembre 2026
Périmètre : Android uniquement (Google Play). Aucun impact sur macOS, Windows, Linux, iOS ou les builds FOSS/F-Droid.

## 1. Résumé

Aika vérifie désormais, de façon discrète et non bloquante, si une nouvelle version est disponible sur Google Play, et propose à l'utilisateur de la télécharger et de l'installer directement depuis l'application, sans jamais télécharger d'APK depuis un serveur externe. Le mécanisme utilise exclusivement l'API officielle **Google Play In-App Updates** (Play Core), via le paquet Flutter `in_app_update`.

Deux types de mise à jour sont pris en charge :

- **Flexible** (par défaut) : téléchargement en arrière-plan, l'utilisateur continue à utiliser Aika normalement ; une fois prête, un message propose de redémarrer pour finaliser l'installation.
- **Immédiate** : UI plein écran officielle de Google Play, bloquante, réservée aux mises à jour critiques (priorité Play Console élevée).

Le choix entre les deux dépend de la **priorité de mise à jour** configurée côté Google Play Console (0 à 5) : au-delà d'un seuil configurable (par défaut 4), Aika demande une mise à jour immédiate ; en dessous, une mise à jour flexible. Ce seuil est volontairement élevé pour que peu de mises à jour soient bloquantes par défaut.

## 2. Bibliothèque utilisée

- **`in_app_update: 5.0.0`** (pub.dev), qui encapsule `com.google.android.play:app-update` (Play Core / Play Update API). Vérifiée au moment de l'implémentation comme non obsolète et compatible Android API 21+.
- Aucune autre dépendance native ajoutée. Aucun secret, clé privée ou identifiant n'est exposé : l'API Play Core fonctionne avec le compte Google Play de l'appareil, sans configuration côté application.

## 3. Fichiers ajoutés

| Fichier | Rôle |
|---|---|
| `app/lib/config/update_config.dart` | Constantes centralisées (activation, fréquence de vérification, seuil de priorité pour la mise à jour immédiate, URL Google Play). Ne dépend pas de Play Core ; reste présent dans les builds FOSS. |
| `app/lib/model/state/update_state.dart` | État (`UpdateState` + `UpdateStatus`), classe simple écrite à la main (pas de `dart_mappable`/codegen, volontairement, voir §7). |
| `app/lib/provider/update_provider.dart` | Logique métier : provider Refena (`ReduxProvider`/`ReduxNotifier`), actions (`CheckForUpdateAction`, `StartFlexibleUpdateAction`, `CompleteFlexibleUpdateAction`, `PerformImmediateUpdateAction`), fonction `maybeCheckForUpdate(ref)` (throttle + déclenchement). Dépend de Play Core → retiré des builds FOSS. |
| `app/lib/widget/dialogs/update_dialog.dart` | Boîte de dialogue Material 3, textes en français (avec repli anglais), thème clair/sombre automatique. Dépend de `update_provider.dart` → retiré des builds FOSS. |
| `app/docs/in-app-updates-2026-09.md` | Ce document. |

## 4. Fichiers modifiés

| Fichier | Modification |
|---|---|
| `app/pubspec.yaml` | Ajout de `in_app_update: 5.0.0 # [FOSS_REMOVE]`. |
| `app/lib/util/native/platform_check.dart` | Ajout de `checkPlatformSupportInAppUpdate()` (Android uniquement). |
| `app/lib/provider/persistence_provider.dart` | Ajout de la clé `ls_last_update_check_millis` et des méthodes `getLastUpdateCheckMillis()` / `setLastUpdateCheckMillis()`, pour limiter la fréquence des vérifications automatiques. |
| `app/lib/util/ui/snackbar.dart` | Ajout de `showSnackBarWithAction()` (bouton d'action, ex. « Redémarrer maintenant »), sans modifier `showSnackBar()` existant. |
| `app/lib/config/init.dart` | Au démarrage de l'app (`appStart`), appelle `maybeCheckForUpdate(ref)` (bloc `[FOSS_REMOVE]`, même schéma que `InitPurchaseStream`). |
| `app/lib/main.dart` | Sur `AppLifecycleState.resumed`, appelle également `maybeCheckForUpdate(ref)` (bloc `[FOSS_REMOVE]`), juste après le rafraîchissement IP existant. |
| `app/lib/pages/about/about_page.dart` | Ajout d'un bouton « Vérifier les mises à jour » (visible seulement sur Android), avec repli « Ouvrir Google Play » si le mécanisme n'est pas utilisable (installation hors Play, etc.) (bloc `[FOSS_REMOVE]`). |
| `support/scripts/remove_proprietary_dependencies.sh` | Ajout du traitement des nouveaux fichiers/blocs `[FOSS_REMOVE]` (`main.dart`, `about_page.dart`) et suppression de `update_provider.dart` / `update_dialog.dart` pour les builds FOSS. |

Aucun fichier lié au partage de fichiers, à la messagerie ou aux téléchargements existants n'a été modifié.

## 5. Fonctionnement détaillé

### 5.1 Déclenchement automatique

- Au démarrage de l'app et à chaque retour au premier plan (`resumed`), `maybeCheckForUpdate(ref)` est appelée.
- Elle vérifie, dans l'ordre : la plateforme (Android uniquement), `UpdateConfig.autoCheckEnabled`, puis le délai écoulé depuis la dernière vérification (`UpdateConfig.minCheckInterval`, 6 heures par défaut, stocké via `persistence_provider`).
- Si toutes les conditions sont réunies, elle enregistre l'horodatage puis déclenche `CheckForUpdateAction` sans attendre son résultat (non bloquant pour l'UI/le démarrage).

### 5.2 Vérification (`CheckForUpdateAction`)

- Appelle `InAppUpdate.checkForUpdate()` (Play Core).
- Si aucune mise à jour n'est disponible → état `notAvailable`, rien n'est affiché.
- Si une mise à jour est disponible → détermine le type (immédiate si priorité ≥ seuil ET autorisée par Play, sinon flexible si autorisée), puis affiche `UpdateDialog` via `Routerino.navigatorKey.currentContext` (permet d'afficher un dialogue sans dépendre d'un `BuildContext` de page spécifique).
- Toute exception (réseau, Play Services absent, etc.) est interceptée : l'état passe à `failed`, rien n'est affiché à l'utilisateur, l'application continue de fonctionner normalement.

### 5.3 Mise à jour flexible

- `StartFlexibleUpdateAction` déclenche `InAppUpdate.startFlexibleUpdate()`.
- Pendant le téléchargement, l'utilisateur continue à utiliser Aika normalement (aucun blocage d'UI).
- Une fois terminé (`AppUpdateResult.success`), un message (snackbar) apparaît avec un bouton « Redémarrer maintenant », qui déclenche `CompleteFlexibleUpdateAction` → `InAppUpdate.completeFlexibleUpdate()` (installe et redémarre l'app).
- En cas d'annulation ou d'échec (`userDeniedUpdate` / `inAppUpdateFailed`), l'état revient à `available` : l'utilisateur peut réessayer plus tard (prochaine vérification automatique, ou bouton manuel).

### 5.4 Mise à jour immédiate

- `PerformImmediateUpdateAction` déclenche `InAppUpdate.performImmediateUpdate()`, qui affiche l'UI plein écran officielle de Google Play et bloque l'utilisation d'Aika jusqu'à la fin (ou l'annulation, si Play l'autorise).
- En cas d'échec ou d'annulation, Aika continue de fonctionner avec la version actuelle (pas de blocage forcé côté application, pas de boucle de nouvelle tentative agressive).

### 5.5 Vérification manuelle

- Page « À propos » → bouton « Vérifier les mises à jour » (visible uniquement sur Android).
- Résultat communiqué par message (snackbar) : déjà à jour, erreur temporaire, ou non disponible (avec proposition d'ouvrir la fiche Google Play d'Aika si configurée).
- Si une mise à jour est trouvée, le dialogue standard s'affiche (même chemin que la vérification automatique).

## 6. Configuration centralisée (`update_config.dart`)

```dart
class UpdateConfig {
  static const bool autoCheckEnabled = true;
  static const Duration minCheckInterval = Duration(hours: 6);
  static const int immediateUpdatePriorityThreshold = 4;
  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.naniger.aika';
}
```

- `autoCheckEnabled` : coupe entièrement les vérifications automatiques si mis à `false` (le bouton manuel reste actif).
- `minCheckInterval` : fréquence maximale des vérifications automatiques.
- `immediateUpdatePriorityThreshold` : priorité Google Play Console (0-5) à partir de laquelle une mise à jour est proposée en mode immédiat/bloquant plutôt que flexible.
- `playStoreUrl` : fiche Google Play officielle d'Aika, utilisée comme repli manuel (page « À propos », cas non compatibles).

Les textes affichés (`update_dialog.dart`, boutons, messages de `about_page.dart`) suivent le même schéma de « localisation légère » déjà utilisé ailleurs dans Aika (`web_send_page.dart`) : une fonction locale `_t({required fr, required en})` qui bascule selon `LocaleSettings.currentLocale`, en l'absence d'environnement de génération de code (`build_runner`/Slang) dans cet environnement de développement.

## 7. Choix techniques notables

- **Pas de `dart_mappable`** pour `UpdateState` : les autres états d'Aika (ex. `PurchaseState`) utilisent `@MappableClass()` avec un fichier généré `*.mapper.dart`. Cette génération nécessite `build_runner`, indisponible dans l'environnement où ce code a été écrit. `UpdateState` est donc une classe immuable simple avec un `copyWith` écrit à la main — fonctionnellement équivalente, sans dépendance de génération de code.
- **Séparation FOSS/Play** : suit exactement le mécanisme existant pour les achats intégrés (`in_app_purchase`) : marqueurs `# [FOSS_REMOVE]` (pubspec.yaml) et `// [FOSS_REMOVE_START]` / `// [FOSS_REMOVE_END]` (fichiers Dart), traités par `support/scripts/remove_proprietary_dependencies.sh`. Aucune dépendance Play Core ne doit se retrouver dans une build F-Droid.
- **Aucune permission de stockage supplémentaire** : Play Core gère lui-même le téléchargement et l'installation ; Aika ne manipule aucun fichier APK.

## 8. Gestion des cas limites

| Cas | Comportement |
|---|---|
| Pas de connexion Internet | `checkForUpdate()` échoue → état `failed`, aucun message intrusif, l'app fonctionne normalement. |
| Aucune mise à jour disponible | État `notAvailable`, rien n'est affiché (vérification auto) ou message discret (vérification manuelle). |
| Mise à jour flexible disponible | Dialogue « Mettre à jour » / « Plus tard », téléchargement en arrière-plan si accepté. |
| Mise à jour immédiate (critique) | Dialogue sans option « Plus tard », lance l'UI bloquante officielle de Google Play. |
| Annulation par l'utilisateur | Aucune erreur affichée ; état revient à `available`, nouvelle tentative possible plus tard. |
| Échec de téléchargement | État `failed`, silencieux pour l'utilisateur (log uniquement), l'app continue de fonctionner. |
| Reprise d'une mise à jour en cours | Gérée nativement par Play Core (l'appel `checkForUpdate()` suivant reflète l'état réel, ex. `readyToInstall` implicite si déjà téléchargée). |
| Installation via APK / site web (hors Play) | `checkPlatformSupportInAppUpdate()` reste vrai (Android), mais `checkForUpdate()` échoue côté Play Core (app non reconnue comme installée depuis Play) → état `unsupported` ou `failed` selon le cas ; le bouton manuel propose alors d'ouvrir la fiche Google Play officielle. |
| Google Play Services indisponible | Exception interceptée → état `failed`/`unsupported`, jamais de faux message d'erreur trompeur. |
| Version Android incompatible | `checkPlatformSupportInAppUpdate()` filtre déjà par plateforme ; en cas d'échec runtime, comportement identique à « Play Services indisponible ». |
| Utilisateur sur une ancienne version d'Aika | Comportement inchangé pour cette implémentation : dès la mise à jour vers une version intégrant cette fonctionnalité, les vérifications démarrent normalement. |

## 9. Prérequis et procédure de test

Cette fonctionnalité **ne peut pas être testée en installant l'APK manuellement** (via `flutter run`, un lien direct, ou un build local hors Play) : Play Core exige que l'application soit installée depuis Google Play (ou un canal de test Play) pour que `checkForUpdate()` retourne un résultat autre qu'« indisponible ».

Prérequis :
1. Un compte Google Play Console avec Aika publiée (au moins en test interne).
2. Deux versions buildées : une version A (déjà publiée, `versionCode` inférieur) et une version B (nouvelle, `versionCode` supérieur), toutes deux signées avec la même clé.

Procédure recommandée — **Internal App Sharing** (le plus rapide, pas d'attente de revue) :
1. Publier la version A sur un canal de test interne (ou Internal App Sharing) et l'installer sur un appareil de test depuis ce lien Play.
2. Builder et publier la version B avec un `versionCode` supérieur, sur le même canal.
3. Sur l'appareil ayant la version A installée (depuis Play), ouvrir Aika : la vérification automatique doit détecter la version B et afficher le dialogue attendu.
4. Vérifier le flux flexible (téléchargement, message « Redémarrer maintenant », redémarrage effectif) et, si testé, le flux immédiat (en configurant temporairement une priorité ≥ seuil sur la version B dans Play Console).

Alternative — **canal de test dédié** (closed testing / open testing) : identique, mais avec une revue Play (délai plus long) ; utile pour un test plus proche des conditions de production réelles.

## 10. Résultats des tests (spécification, statique uniquement)

**Important** : cet environnement de développement ne dispose d'aucun SDK Flutter/Dart/Android (`flutter analyze`, `flutter build`, un émulateur, etc. sont indisponibles ici). Toutes les modifications ont donc été :

- vérifiées structurellement (équilibre des accolades/parenthèses/crochets sur chaque fichier créé ou modifié) ;
- vérifiées par relecture manuelle attentive du code par rapport aux patterns déjà éprouvés et existants dans le code base (Refena, `checkPlatform*`, `persistence_provider`, `SnackbarExt`, `Routerino.navigatorKey`, etc.) ;
- **non compilées ni exécutées** faute d'outillage disponible ici.

Les 12 tests listés dans la spécification (aucune mise à jour disponible, nouvelle version disponible, mise à jour flexible, mise à jour immédiate, annulation utilisateur, échec de téléchargement, reprise d'une mise à jour en cours, absence de connexion, installation hors Play, installation depuis un canal de test Play, vérification du thème sombre, non-régression des fonctionnalités existantes) doivent donc être exécutés par vous, sur un appareil réel, avec un build signé publié sur Google Play (voir §9), avant toute mise en production.

## 11. Limitations restantes

- **Non compilé/exécuté** dans cet environnement (voir §10) : une vérification `flutter analyze` / `flutter build apk` / test manuel sur appareil reste nécessaire avant publication.
- Le typage exact de certains champs de l'API `in_app_update` (ex. nullabilité de `updatePriority`) s'appuie sur la documentation publique du paquet au moment de l'écriture et n'a pas pu être vérifié par compilation ; à confirmer lors du premier `flutter pub get` + `flutter analyze`.
- Les textes de l'interface utilisent un mécanisme de « localisation légère » (`_t(fr:, en:)`) plutôt que le système Slang généré (`gen/strings*.g.dart`), par cohérence avec le reste du code écrit dans cet environnement sans `build_runner`. Une intégration complète dans Slang (fichiers de traduction) peut être faite ultérieurement, quand l'outillage de génération sera disponible.
- Le comportement exact de reprise après une mise à jour flexible interrompue (ex. app fermée puis rouverte pendant le téléchargement) dépend entièrement de Play Core côté natif ; non testable ici faute d'appareil/toolchain.

## 12. Publier une nouvelle version sur Google Play

1. Incrémenter `version` dans `app/pubspec.yaml` (`versionName+versionCode`, ex. `1.0.3+4`).
2. `flutter build appbundle --release` (ou APK signé selon le canal utilisé).
3. Dans Google Play Console : créer une nouvelle release sur le canal souhaité (interne, fermé, ouvert ou production), joindre l'artefact, définir la **priorité de mise à jour** (0-5) si une mise à jour immédiate est souhaitée pour cette version (`In-app updates` → `Update priority` dans la fiche de la release, ou via l'API Play Developer).
4. Publier la release. Les appareils ayant une version antérieure installée depuis Play commenceront à voir la mise à jour proposée par Aika dans un délai qui dépend de la propagation côté Google Play (généralement quelques heures).
