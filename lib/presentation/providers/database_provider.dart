import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';

/// Single shared database instance for the app's lifetime. Every
/// repository provider below reads this instead of constructing its own
/// AppDatabase, so all reads/writes go through one connection.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Live view of the single AppSettingsTable row. Using `.watchSingle()`
/// means the theme mode and onboarding flag are always read from the
/// database, never cached separately — so there is exactly one source
/// of truth for "has onboarding been completed".
final appSettingsProvider = StreamProvider<AppSettingsTableData>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.appSettingsTable).watchSingle();
});
