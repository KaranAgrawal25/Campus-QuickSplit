import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/tables.dart';
import 'cloud_id_repository.dart';
import 'sync_repository.dart';

/// Applies Firebase snapshots to SQLite. The UI never reads cloud data directly.
/// Every upsert first resolves a cloud ID through [CloudIdRepository], making
/// replayed pull events harmless.
class DatabaseSyncChangeApplier implements SyncChangeApplier {
  DatabaseSyncChangeApplier(this._db);
  final AppDatabase _db;
  final Map<String, String> _userAliases = {};

  @override
  Future<void> apply(List<CloudSyncChange> changes) async {
    _userAliases.clear();
    await _db.transaction(() async {
      // A Firestore query is ordered by server timestamps, not by foreign
      // key dependencies. Replaying people and groups first means a clean
      // reinstall can resolve memberships and financial rows in the same
      // pull, rather than silently dropping unresolved references.
      const order = [
        'user',
        'group',
        'membership',
        'invite',
        'expense',
        'recurring_template',
        'settlement',
        'reminder',
      ];
      for (final type in order) {
        for (final change in changes.where((item) => item.entityType == type)) {
          switch (change.entityType) {
            case 'user':
              await _user(change);
            case 'group':
              await _group(change);
            case 'membership':
              await _membership(change);
            case 'invite':
              await _invite(change);
            case 'expense':
              await _expense(change);
            case 'recurring_template':
              await _recurringTemplate(change);
            case 'settlement':
              await _settlement(change);
            case 'reminder':
              await _reminder(change);
          }
        }
      }
    });
    _userAliases.clear();
  }

  Future<String?> _local(String type, Object? cloudId) async {
    if (cloudId is! String) return null;
    if (type == 'user' && _userAliases.containsKey(cloudId)) {
      return _userAliases[cloudId];
    }
    return CloudIdRepository(_db).localForCloud(type, cloudId);
  }

  Future<void> _user(CloudSyncChange change) async {
    final payload = change.payload;
    var existing = await _local('user', change.entityId);
    var isCurrentUser = payload['isCurrentUser'] == true;
    // A stale legacy operation may describe the Firebase-mapped local owner
    // as a normal member. The persisted local owner wins in that conflict;
    // accepting the stale false value would briefly remove the only current
    // user and send the startup gate back to onboarding.
    if (!isCurrentUser && existing != null) {
      final mapped = await (_db.select(
        _db.users,
      )..where((user) => user.id.equals(existing!))).getSingleOrNull();
      isCurrentUser = mapped?.isCurrentUser ?? false;
    }
    if (isCurrentUser) {
      // Older clients could serialize the account owner with a random cloud
      // UUID and later with their Firebase UID. Both identities are the same
      // person. Link every such historical cloud ID to the one local current
      // user so memberships, payments, and shares resolve to one stable row.
      final current = await (_db.select(
        _db.users,
      )..where((user) => user.isCurrentUser.equals(true))).getSingleOrNull();
      if (current != null && existing == null) {
        existing = current.id;
        await CloudIdRepository(_db).link('user', existing, change.entityId);
      }
      await (_db.update(_db.users)..where(
            (user) =>
                user.isCurrentUser.equals(true) &
                (existing == null
                    ? const Constant(true)
                    : user.id.equals(existing).not()),
          ))
          .write(const UsersCompanion(isCurrentUser: Value(false)));
    }
    if (existing == null) {
      final local = await _db
          .into(_db.users)
          .insertReturning(
            UsersCompanion.insert(
              name: payload['name'] as String? ?? 'Member',
              initials: payload['initials'] as String? ?? '?',
              phoneNumber: Value(payload['phoneNumber'] as String?),
              email: Value(payload['email'] as String?),
              upiId: Value(payload['upiId'] as String?),
              isCurrentUser: Value(isCurrentUser),
              createdAt: Value(_time(payload['createdAt'])),
              updatedAt: Value(_time(payload['updatedAt'])),
            ),
          );
      await CloudIdRepository(_db).link('user', local.id, change.entityId);
      _userAliases[change.entityId] = local.id;
      return;
    }
    await (_db.update(_db.users)..where((u) => u.id.equals(existing!))).write(
      UsersCompanion(
        name: Value(payload['name'] as String? ?? 'Member'),
        initials: Value(payload['initials'] as String? ?? '?'),
        phoneNumber: Value(payload['phoneNumber'] as String?),
        email: Value(payload['email'] as String?),
        upiId: Value(payload['upiId'] as String?),
        isCurrentUser: Value(isCurrentUser),
        updatedAt: Value(_time(payload['updatedAt'])),
      ),
    );
    _userAliases[change.entityId] = existing;
  }

  Future<void> _group(CloudSyncChange change) async {
    final existing = await _local('group', change.entityId);
    final name = change.payload['name'] as String? ?? 'Untitled group';
    if (existing == null) {
      final local = await _db
          .into(_db.groups)
          .insertReturning(
            GroupsCompanion.insert(
              name: name,
              isArchived: Value(change.payload['isArchived'] == true),
              createdAt: Value(_time(change.payload['createdAt'])),
            ),
          );
      await CloudIdRepository(_db).link('group', local.id, change.entityId);
      return;
    }
    await (_db.update(_db.groups)..where((g) => g.id.equals(existing))).write(
      GroupsCompanion(
        name: Value(name),
        isArchived: Value(change.payload['isArchived'] == true),
        createdAt: Value(_time(change.payload['createdAt'])),
      ),
    );
  }

  Future<void> _membership(CloudSyncChange change) async {
    final groupId = await _local('group', change.payload['groupId']);
    final localUserId = await _local('user', change.payload['userId']);
    if (groupId == null || localUserId == null) return;
    var userId = localUserId;
    if (change.payload['removed'] == true) {
      await (_db.delete(_db.groupMembers)..where(
            (row) => row.groupId.equals(groupId) & row.userId.equals(userId),
          ))
          .go();
      return;
    }
    // Earlier cloud builds could assign a second cloud identity to the same
    // manually-entered person. Collapse an exact duplicate within this group
    // before adding membership, then alias the old cloud ID to the canonical
    // local row so later expense references keep their real amounts.
    final incoming = await (_db.select(
      _db.users,
    )..where((user) => user.id.equals(userId))).getSingle();
    final existingMembers = _db.select(_db.users).join([
      innerJoin(
        _db.groupMembers,
        _db.groupMembers.userId.equalsExp(_db.users.id),
      ),
    ])..where(_db.groupMembers.groupId.equals(groupId));
    for (final row in await existingMembers.get()) {
      final candidate = row.readTable(_db.users);
      if (candidate.id != userId &&
          !candidate.isCurrentUser &&
          !incoming.isCurrentUser &&
          _samePerson(candidate, incoming)) {
        await CloudIdRepository(
          _db,
        ).link('user', candidate.id, change.payload['userId'] as String);
        userId = candidate.id;
        break;
      }
    }
    await _db
        .into(_db.groupMembers)
        .insert(
          GroupMembersCompanion.insert(
            groupId: groupId,
            userId: userId,
            joinedAt: Value(_time(change.payload['joinedAt'])),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _invite(CloudSyncChange change) async {
    final groupId = await _local('group', change.payload['groupId']);
    if (groupId == null) return;
    final existing = await _local('invite', change.entityId);
    final values = InvitesCompanion(
      groupId: Value(groupId),
      token: Value(change.payload['token'] as String? ?? ''),
      expiresAt: Value(_nullableTime(change.payload['expiresAt'])),
      isActive: Value(change.payload['isActive'] != false),
    );
    if (existing == null) {
      final local = await _db
          .into(_db.invites)
          .insertReturning(
            InvitesCompanion.insert(
              groupId: groupId,
              token: change.payload['token'] as String,
              expiresAt: Value(_nullableTime(change.payload['expiresAt'])),
              isActive: Value(change.payload['isActive'] != false),
            ),
          );
      await CloudIdRepository(_db).link('invite', local.id, change.entityId);
    } else {
      await (_db.update(
        _db.invites,
      )..where((i) => i.id.equals(existing))).write(values);
    }
  }

  Future<void> _expense(CloudSyncChange change) async {
    final groupId = await _local('group', change.payload['groupId']);
    if (groupId == null) return;
    final existing = await _local('expense', change.entityId);
    final values = ExpensesCompanion(
      groupId: Value(groupId),
      title: Value(change.payload['title'] as String? ?? 'Untitled expense'),
      description: Value(change.payload['description'] as String?),
      totalAmountPaise: Value(change.payload['totalAmountPaise'] as int? ?? 0),
      category: Value(change.payload['category'] as String? ?? 'Other'),
      splitType: Value(_splitType(change.payload['splitType'] as String?)),
      createdAt: Value(_time(change.payload['createdAt'])),
      isDeleted: Value(change.payload['isDeleted'] == true),
    );
    final localId =
        existing ??
        (await _db
                .into(_db.expenses)
                .insertReturning(
                  ExpensesCompanion.insert(
                    groupId: groupId,
                    title:
                        change.payload['title'] as String? ??
                        'Untitled expense',
                    totalAmountPaise:
                        change.payload['totalAmountPaise'] as int? ?? 0,
                    category: change.payload['category'] as String? ?? 'Other',
                    splitType: Value(
                      _splitType(change.payload['splitType'] as String?),
                    ),
                    createdAt: Value(_time(change.payload['createdAt'])),
                    isDeleted: Value(change.payload['isDeleted'] == true),
                  ),
                ))
            .id;
    if (existing == null) {
      await CloudIdRepository(_db).link('expense', localId, change.entityId);
    } else {
      await (_db.update(
        _db.expenses,
      )..where((e) => e.id.equals(localId))).write(values);
    }
    await (_db.delete(
      _db.expensePayments,
    )..where((p) => p.expenseId.equals(localId))).go();
    await (_db.delete(
      _db.expenseParticipants,
    )..where((p) => p.expenseId.equals(localId))).go();
    for (final item in (change.payload['payments'] as List? ?? const [])) {
      final row = Map<String, Object?>.from(item as Map);
      final userId = await _local('user', row['userId']);
      if (userId != null) {
        await _db
            .into(_db.expensePayments)
            .insert(
              ExpensePaymentsCompanion.insert(
                expenseId: localId,
                userId: userId,
                amountPaidPaise: row['amountPaidPaise'] as int,
              ),
            );
      }
    }
    for (final item in (change.payload['participants'] as List? ?? const [])) {
      final row = Map<String, Object?>.from(item as Map);
      final userId = await _local('user', row['userId']);
      if (userId != null) {
        await _db
            .into(_db.expenseParticipants)
            .insert(
              ExpenseParticipantsCompanion.insert(
                expenseId: localId,
                userId: userId,
                amountOwedPaise: row['amountOwedPaise'] as int,
                ratio: Value(row['ratio'] as int?),
              ),
            );
      }
    }
  }

  Future<void> _settlement(CloudSyncChange change) async {
    final groupId = await _local('group', change.payload['groupId']);
    final fromId = await _local('user', change.payload['fromUserId']);
    final toId = await _local('user', change.payload['toUserId']);
    if (groupId == null || fromId == null || toId == null) return;
    final existing = await _local('settlement', change.entityId);
    final values = SettlementsCompanion(
      groupId: Value(groupId),
      fromUserId: Value(fromId),
      toUserId: Value(toId),
      amountPaise: Value(change.payload['amountPaise'] as int? ?? 0),
      note: Value(change.payload['note'] as String?),
      status: Value(
        SettlementStatus.values.byName(
          change.payload['status'] as String? ?? 'completed',
        ),
      ),
      createdAt: Value(_time(change.payload['createdAt'])),
    );
    if (existing == null) {
      final local = await _db
          .into(_db.settlements)
          .insertReturning(
            SettlementsCompanion.insert(
              groupId: groupId,
              fromUserId: fromId,
              toUserId: toId,
              amountPaise: change.payload['amountPaise'] as int? ?? 0,
              status: Value(
                SettlementStatus.values.byName(
                  change.payload['status'] as String? ?? 'completed',
                ),
              ),
              createdAt: Value(_time(change.payload['createdAt'])),
              note: Value(change.payload['note'] as String?),
            ),
          );
      await CloudIdRepository(
        _db,
      ).link('settlement', local.id, change.entityId);
    } else {
      await (_db.update(
        _db.settlements,
      )..where((s) => s.id.equals(existing))).write(values);
    }
  }

  Future<void> _recurringTemplate(CloudSyncChange change) async {
    final sourceExpenseId = await _local(
      'expense',
      change.payload['sourceExpenseId'],
    );
    if (sourceExpenseId == null) return;
    final existing = await _local('recurring_template', change.entityId);
    final values = RecurringExpenseTemplatesCompanion(
      sourceExpenseId: Value(sourceExpenseId),
      intervalDays: Value(change.payload['intervalDays'] as int? ?? 1),
      nextDueAt: Value(_time(change.payload['nextDueAt'])),
      isActive: Value(change.payload['isActive'] != false),
      createdAt: Value(_time(change.payload['createdAt'])),
    );
    if (existing == null) {
      final local = await _db
          .into(_db.recurringExpenseTemplates)
          .insertReturning(
            RecurringExpenseTemplatesCompanion.insert(
              sourceExpenseId: sourceExpenseId,
              intervalDays: change.payload['intervalDays'] as int? ?? 1,
              nextDueAt: _time(change.payload['nextDueAt']),
              isActive: Value(change.payload['isActive'] != false),
              createdAt: Value(_time(change.payload['createdAt'])),
            ),
          );
      await CloudIdRepository(
        _db,
      ).link('recurring_template', local.id, change.entityId);
    } else {
      await (_db.update(
        _db.recurringExpenseTemplates,
      )..where((row) => row.id.equals(existing))).write(values);
    }
  }

  Future<void> _reminder(CloudSyncChange change) async {
    final existing = await _local('reminder', change.entityId);
    final frequency = ReminderFrequency.values.firstWhere(
      (value) => value.name == change.payload['frequency'],
      orElse: () => ReminderFrequency.once,
    );
    final values = ReminderSchedulesCompanion(
      title: Value(change.payload['title'] as String? ?? 'Balance reminder'),
      body: Value(change.payload['body'] as String? ?? 'Review your balance.'),
      frequency: Value(frequency),
      hour: Value(change.payload['hour'] as int? ?? 9),
      minute: Value(change.payload['minute'] as int? ?? 0),
      weekday: Value(change.payload['weekday'] as int?),
      dayOfMonth: Value(change.payload['dayOfMonth'] as int?),
      scheduledAt: Value(_time(change.payload['scheduledAt'])),
      nextScheduledAt: Value(_time(change.payload['nextScheduledAt'])),
      isEnabled: Value(change.payload['isEnabled'] != false),
      createdAt: Value(_time(change.payload['createdAt'])),
      updatedAt: Value(_time(change.payload['updatedAt'])),
    );
    if (existing == null) {
      final local = await _db
          .into(_db.reminderSchedules)
          .insertReturning(
            ReminderSchedulesCompanion.insert(
              title: change.payload['title'] as String? ?? 'Balance reminder',
              body: change.payload['body'] as String? ?? 'Review your balance.',
              frequency: frequency,
              hour: change.payload['hour'] as int? ?? 9,
              minute: change.payload['minute'] as int? ?? 0,
              weekday: Value(change.payload['weekday'] as int?),
              dayOfMonth: Value(change.payload['dayOfMonth'] as int?),
              scheduledAt: _time(change.payload['scheduledAt']),
              nextScheduledAt: _time(change.payload['nextScheduledAt']),
              isEnabled: Value(change.payload['isEnabled'] != false),
              createdAt: Value(_time(change.payload['createdAt'])),
              updatedAt: Value(_time(change.payload['updatedAt'])),
            ),
          );
      await CloudIdRepository(_db).link('reminder', local.id, change.entityId);
    } else {
      await (_db.update(
        _db.reminderSchedules,
      )..where((row) => row.id.equals(existing))).write(values);
    }
  }

  DateTime _time(Object? value) =>
      DateTime.tryParse(value as String? ?? '') ?? DateTime.now();
  DateTime? _nullableTime(Object? value) => value == null ? null : _time(value);
  bool _samePerson(User first, User second) =>
      first.name.trim().toLowerCase() == second.name.trim().toLowerCase() &&
      first.initials == second.initials &&
      first.email == second.email &&
      first.phoneNumber == second.phoneNumber;
  SplitTypeDb _splitType(String? value) => SplitTypeDb.values.firstWhere(
    (type) => type.name == value,
    orElse: () => SplitTypeDb.equal,
  );
}
