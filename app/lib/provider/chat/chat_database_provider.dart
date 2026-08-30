import 'package:localsend_app/model/chat/chat_database.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Exposes the single [ChatDatabase] instance for the whole app.
///
/// Overridden with a real, eagerly-opened [ChatDatabase.defaults] in
/// `preInit()` (see `config/init.dart`), mirroring how `persistenceProvider`
/// is wired. Opening the underlying sqlite file is cheap and lazy on
/// drift's side (it only happens on the first actual query), so doing this
/// eagerly at container-build time does not slow down app startup.
final chatDatabaseProvider = Provider<ChatDatabase>((ref) {
  throw Exception('chatDatabaseProvider not initialized');
});
