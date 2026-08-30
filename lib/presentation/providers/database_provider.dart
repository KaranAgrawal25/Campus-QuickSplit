import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/sync_repository.dart';
import '../../data/repositories/firebase_sync_transport.dart';
import '../../data/repositories/database_sync_change_applier.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../core/sync/cloud_runtime.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/backup_repository.dart';
import '../../data/repositories/recurring_expense_repository.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../data/repositories/export_repository.dart';

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

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  if (!CloudRuntime.isInitialized) return SyncRepository(db);
  return SyncRepository(
    db,
    transport: FirebaseSyncTransport(
      firebase_auth.FirebaseAuth.instance,
      FirebaseFirestore.instance,
      db,
    ),
    applier: DatabaseSyncChangeApplier(db),
  );
});

final cloudAuthRepositoryProvider = Provider<FirebaseAuthRepository?>(
  (ref) => CloudRuntime.isInitialized
      ? FirebaseAuthRepository(firebase_auth.FirebaseAuth.instance)
      : null,
);

/// Firebase Auth persists a completed sign-in locally. Listening here keeps
/// cloud controls current without making core expense screens depend on it.
final cloudAuthStateProvider = StreamProvider<firebase_auth.User?>((ref) {
  final auth = ref.watch(cloudAuthRepositoryProvider);
  if (auth == null) return Stream.value(null);
  return auth.authStateChanges.map((user) {
    debugPrint(
      '[QuickSplit auth] state=${user == null ? 'signed-out' : 'authenticated'} uid=${user?.uid}',
    );
    return user;
  });
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncRepositoryProvider).watchStatus();
});

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(appDatabaseProvider));
});

final exportRepositoryProvider = Provider<ExportRepository>((ref) {
  return ExportRepository(ref.watch(appDatabaseProvider));
});

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(ref.watch(appDatabaseProvider));
});

final recurringExpenseRepositoryProvider = Provider<RecurringExpenseRepository>(
  (ref) {
    return RecurringExpenseRepository(ref.watch(appDatabaseProvider));
  },
);

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository(ref.watch(appDatabaseProvider));
});
