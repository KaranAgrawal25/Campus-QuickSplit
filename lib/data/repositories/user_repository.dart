import 'package:drift/drift.dart';

import '../../core/payments/upi_payment.dart';
import '../database/app_database.dart';
import 'sync_repository.dart';

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

    final validationError = validateDisplayName(name);
    if (validationError != null) {
      throw ArgumentError.value(name, 'name', validationError);
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
            updatedAt: Value(DateTime.now()),
          ),
        );

    await _queueUser(id);
    return id;
  }

  /// Repairs a local profile after a cloud restore from an older build left
  /// every user row marked as a member. It adopts the best matching existing
  /// record first, preserving memberships, expense shares, and payments.
  Future<User> recoverCurrentUser({required String name, String? email}) async {
    final trimmedName = name.trim().isEmpty ? 'QuickSplit user' : name.trim();
    return _db.transaction(() async {
      final existingCurrent = await getCurrentUser();
      if (existingCurrent != null) return existingCurrent;
      final allUsers = await _db.select(_db.users).get();
      final normalizedEmail = email?.trim().toLowerCase();
      User? candidate;
      if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
        candidate = allUsers
            .where(
              (user) => user.email?.trim().toLowerCase() == normalizedEmail,
            )
            .firstOrNull;
      }
      candidate ??= allUsers
          .where(
            (user) =>
                user.name.trim().toLowerCase() == trimmedName.toLowerCase(),
          )
          .firstOrNull;
      if (candidate == null) {
        candidate = await _db
            .into(_db.users)
            .insertReturning(
              UsersCompanion.insert(
                name: trimmedName,
                initials: _deriveInitials(trimmedName),
                email: Value(normalizedEmail),
                isCurrentUser: const Value(true),
                updatedAt: Value(DateTime.now()),
              ),
            );
      } else {
        await (_db.update(
          _db.users,
        )..where((user) => user.id.equals(candidate!.id))).write(
          UsersCompanion(
            isCurrentUser: const Value(true),
            email: Value(normalizedEmail ?? candidate.email),
            updatedAt: Value(DateTime.now()),
          ),
        );
        candidate = await (_db.select(
          _db.users,
        )..where((user) => user.id.equals(candidate!.id))).getSingle();
      }
      final recovered = candidate;
      await _queueUser(recovered);
      return recovered;
    });
  }

  Future<void> updateProfile({
    required String userId,
    required String name,
    String? email,
    String? phoneNumber,
    String? upiId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Display name is required');
    final phone = phoneNumber?.trim();
    final normalizedEmail = email?.trim();
    if (normalizedEmail != null &&
        normalizedEmail.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw ArgumentError('Enter a valid email address');
    }
    if (phone != null &&
        phone.isNotEmpty &&
        !RegExp(r'^\+?[0-9][0-9 -]{7,14}$').hasMatch(phone)) {
      throw ArgumentError('Enter a valid phone number');
    }
    final upi = upiId?.trim();
    if (upi != null && upi.isNotEmpty && !UpiPayment.isValidUpiId(upi)) {
      throw ArgumentError('Enter a valid UPI ID');
    }
    await (_db.update(
      _db.users,
    )..where((user) => user.id.equals(userId))).write(
      UsersCompanion(
        name: Value(trimmedName),
        initials: Value(_deriveInitials(trimmedName)),
        phoneNumber: Value(phone?.isEmpty ?? true ? null : phone),
        email: Value(normalizedEmail?.isEmpty ?? true ? null : normalizedEmail),
        upiId: Value(upi?.isEmpty ?? true ? null : upi),
        updatedAt: Value(DateTime.now()),
      ),
    );
    final user = await (_db.select(
      _db.users,
    )..where((row) => row.id.equals(userId))).getSingle();
    await _queueUser(user);
  }

  Future<void> _queueUser(User user) => SyncRepository(_db).enqueueUpsert(
    entityType: 'user',
    entityId: user.id,
    payload: {
      'id': user.id,
      'name': user.name,
      'initials': user.initials,
      'phoneNumber': user.phoneNumber,
      'email': user.email,
      'upiId': user.upiId,
      'isCurrentUser': user.isCurrentUser,
      'createdAt': user.createdAt.toUtc().toIso8601String(),
      'updatedAt': user.updatedAt.toUtc().toIso8601String(),
    },
  );

  /// Shared UI and persistence validation for a local profile name. Keeping
  /// it here means onboarding cannot accept a value that a repository write
  /// would later reject.
  static String? validateDisplayName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter your name';
    if (trimmed.length > 60) return 'Name is too long';
    return null;
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
