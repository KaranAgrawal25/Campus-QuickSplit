import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Handles all reads/writes for [Users]. This is the only place that
/// knows how a "current user" (the device owner) is represented in the
/// schema — everything else asks this repository, rather than querying
/// `isCurrentUser` directly.
class UserRepository {
  UserRepository(this._db);

  final AppDatabase _db;

  /// Emits the current device user, or null if onboarding hasn't run
  /// yet. Callers use this to route between onboarding and the
  /// dashboard, and it stays live so a name change (Settings, later
  /// phase) reflects everywhere instantly.
  Stream<User?> watchCurrentUser() {
    final query = _db.select(_db.users)
      ..where((u) => u.isCurrentUser.equals(true));
    return query.watchSingleOrNull();
  }

  Future<User?> getCurrentUser() async {
    final query = _db.select(_db.users)
      ..where((u) => u.isCurrentUser.equals(true));
    return query.getSingleOrNull();
  }

  /// Creates the local device-owner user during onboarding. Throws a
  /// [StateError] if a current user already exists — onboarding must
  /// only ever run once per install.
  Future<User> createCurrentUser(String name) async {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }

    final existing = await getCurrentUser();

    if (existing != null) {
      throw StateError('A current user already exists');
    }

    final id = await _db
        .into(_db.users)
        .insertReturning(
          UsersCompanion.insert(
            name: trimmed,
            initials: _deriveInitials(trimmed),
            isCurrentUser: const Value(true),
          ),
        );

    return id;
  }

  static String _deriveInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
