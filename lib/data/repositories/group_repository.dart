import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'sync_repository.dart';

class GroupWithMembers {
  const GroupWithMembers({required this.group, required this.members});
  final Group group;
  final List<User> members;
}

class GroupRepository {
  GroupRepository(this._db);
  final AppDatabase _db;

  Stream<List<Group>> watchGroups() {
    final query = _db.select(_db.groups)
      ..where((group) => group.isArchived.equals(false))
      ..orderBy([(group) => OrderingTerm.desc(group.createdAt)]);
    return query.watch();
  }

  /// Used by portable, offline QR joins to avoid creating a second local copy
  /// if the same code is scanned again after a successful join.
  Future<Group?> findActiveByName(String name) async {
    final normalized = name.trim().toLowerCase();
    final groups = await (_db.select(
      _db.groups,
    )..where((group) => group.isArchived.equals(false))).get();
    for (final group in groups) {
      if (group.name.trim().toLowerCase() == normalized) return group;
    }
    return null;
  }

  Stream<List<Group>> watchArchivedGroups() {
    final query = _db.select(_db.groups)
      ..where((group) => group.isArchived.equals(true))
      ..orderBy([(group) => OrderingTerm.desc(group.createdAt)]);
    return query.watch();
  }

  Stream<GroupWithMembers?> watchGroup(String groupId) async* {
    // Group detail presents both the group and its members. Watching only the
    // group row left the UI stale after adding a member or editing a profile.
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.groups, _db.groupMembers, _db.users},
        )
        .watch();
    await for (final _ in trigger) {
      final group = await (_db.select(
        _db.groups,
      )..where((g) => g.id.equals(groupId))).getSingleOrNull();
      if (group == null) {
        yield null;
        continue;
      }
      final members = await _membersFor(groupId);
      yield GroupWithMembers(group: group, members: members);
    }
  }

  Future<String> createGroup({
    required String name,
    required String currentUserId,
    required List<String> memberNames,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Group name is required');
    return _db.transaction(() async {
      final currentUser = await (_db.select(
        _db.users,
      )..where((user) => user.id.equals(currentUserId))).getSingleOrNull();
      if (currentUser == null) {
        throw StateError('Your local user no longer exists');
      }
      final group = await _db
          .into(_db.groups)
          .insertReturning(GroupsCompanion.insert(name: trimmed));
      await _db
          .into(_db.groupMembers)
          .insert(
            GroupMembersCompanion.insert(
              groupId: group.id,
              userId: currentUserId,
            ),
          );
      for (final rawName in memberNames) {
        final memberName = rawName.trim();
        if (memberName.isEmpty) continue;
        // The form only supplies a name for a new person. If it identifies
        // the device owner, retain their existing stable id instead of
        // creating a second local record for the same person.
        if (_sameDisplayName(memberName, currentUser.name)) continue;
        final user = await _db
            .into(_db.users)
            .insertReturning(
              UsersCompanion.insert(
                name: memberName,
                initials: _initials(memberName),
                updatedAt: Value(DateTime.now()),
              ),
            );
        await _db
            .into(_db.groupMembers)
            .insert(
              GroupMembersCompanion.insert(groupId: group.id, userId: user.id),
            );
      }
      await _queueGroup(group);
      // Membership records contain only stable ids. Persist every referenced
      // person first so a fresh device can resolve those ids while replaying
      // the membership operation. This is deliberately identity-based: names
      // are display data and must never be used as cloud keys.
      for (final member in await _membersFor(group.id)) {
        await _queueUser(member);
      }
      await _queueMembership(group.id, currentUserId);
      final members = await _membersFor(group.id);
      for (final member in members.where((user) => user.id != currentUserId)) {
        await _queueMembership(group.id, member.id);
      }
      return group.id;
    });
  }

  Future<void> rename(String groupId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Group name is required');
    await (_db.update(_db.groups)..where((g) => g.id.equals(groupId))).write(
      GroupsCompanion(name: Value(trimmed)),
    );
    await _queueGroupById(groupId);
  }

  Future<void> archive(String groupId) =>
      (_db.update(_db.groups)..where((g) => g.id.equals(groupId)))
          .write(const GroupsCompanion(isArchived: Value(true)))
          .then((_) => _queueGroupById(groupId));

  Future<void> restore(String groupId) =>
      (_db.update(_db.groups)..where((g) => g.id.equals(groupId)))
          .write(const GroupsCompanion(isArchived: Value(false)))
          .then((_) => _queueGroupById(groupId));

  /// Permanent removal is safe only before a group has financial history.
  /// Historical groups must be archived instead, preserving every expense and
  /// settlement that contributed to a past balance.
  Future<void> deleteEmptyGroup(String groupId) async {
    final expenses = await (_db.select(
      _db.expenses,
    )..where((expense) => expense.groupId.equals(groupId))).get();
    final settlements = await (_db.select(
      _db.settlements,
    )..where((settlement) => settlement.groupId.equals(groupId))).get();
    if (expenses.isNotEmpty || settlements.isNotEmpty) {
      throw StateError('Groups with financial history can only be archived');
    }
    await (_db.delete(
      _db.groups,
    )..where((group) => group.id.equals(groupId))).go();
  }

  Future<User> addMember(
    String groupId,
    String name, {
    required String currentUserId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Member name is required');
    final currentUser = await (_db.select(
      _db.users,
    )..where((user) => user.id.equals(currentUserId))).getSingleOrNull();
    if (currentUser != null && _sameDisplayName(trimmed, currentUser.name)) {
      await addExistingMember(groupId, currentUserId);
      return currentUser;
    }
    return _db.transaction(() async {
      final user = await _db
          .into(_db.users)
          .insertReturning(
            UsersCompanion.insert(
              name: trimmed,
              initials: _initials(trimmed),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await _db
          .into(_db.groupMembers)
          .insert(
            GroupMembersCompanion.insert(groupId: groupId, userId: user.id),
          );
      await _queueUser(user);
      await _queueMembership(groupId, user.id);
      return user;
    });
  }

  /// Adds an existing local user by its stable id. Display names are never
  /// used to decide membership; the composite primary key is the durable
  /// final guard against duplicate membership rows.
  Future<void> addExistingMember(String groupId, String userId) async {
    final user = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(userId))).getSingleOrNull();
    if (user == null) {
      throw StateError('That member no longer exists');
    }
    final existing =
        await (_db.select(_db.groupMembers)..where(
              (m) => m.groupId.equals(groupId) & m.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      throw StateError('${user.name} is already in this group');
    }
    await _db
        .into(_db.groupMembers)
        .insert(GroupMembersCompanion.insert(groupId: groupId, userId: userId));
    await _queueUser(user);
    await _queueMembership(groupId, userId);
  }

  Future<void> removeMember(String groupId, String userId) async {
    final participantHistory =
        _db.select(_db.expenseParticipants).join([
          innerJoin(
            _db.expenses,
            _db.expenses.id.equalsExp(_db.expenseParticipants.expenseId),
          ),
        ])..where(
          _db.expenseParticipants.userId.equals(userId) &
              _db.expenses.groupId.equals(groupId),
        );
    final settlementHistory =
        await (_db.select(_db.settlements)..where(
              (settlement) =>
                  settlement.groupId.equals(groupId) &
                  (settlement.fromUserId.equals(userId) |
                      settlement.toUserId.equals(userId)),
            ))
            .get();
    if ((await participantHistory.get()).isNotEmpty ||
        settlementHistory.isNotEmpty) {
      throw StateError('This member has expense history and cannot be removed');
    }
    await (_db.delete(
      _db.groupMembers,
    )..where((m) => m.groupId.equals(groupId) & m.userId.equals(userId))).go();
    await SyncRepository(_db).enqueueUpsert(
      entityType: 'membership',
      entityId: '$groupId:$userId',
      payload: {'groupId': groupId, 'userId': userId, 'removed': true},
    );
  }

  Future<List<User>> members(String groupId) => _membersFor(groupId);

  Future<void> _queueGroupById(String groupId) async {
    final group = await (_db.select(
      _db.groups,
    )..where((row) => row.id.equals(groupId))).getSingleOrNull();
    if (group != null) await _queueGroup(group);
  }

  Future<void> _queueGroup(Group group) => SyncRepository(_db).enqueueUpsert(
    entityType: 'group',
    entityId: group.id,
    payload: {
      'id': group.id,
      'name': group.name,
      'isArchived': group.isArchived,
      'createdAt': group.createdAt.toUtc().toIso8601String(),
    },
  );

  Future<void> _queueMembership(String groupId, String userId) =>
      SyncRepository(_db).enqueueUpsert(
        entityType: 'membership',
        entityId: '$groupId:$userId',
        payload: {
          'groupId': groupId,
          'userId': userId,
          'removed': false,
          'joinedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );

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

  Future<List<User>> _membersFor(String groupId) {
    final query = _db.select(_db.users).join([
      innerJoin(
        _db.groupMembers,
        _db.groupMembers.userId.equalsExp(_db.users.id),
      ),
    ])..where(_db.groupMembers.groupId.equals(groupId));
    return query.get().then((rows) {
      final usersById = <String, User>{};
      for (final row in rows) {
        final user = row.readTable(_db.users);
        usersById.putIfAbsent(user.id, () => user);
      }
      return usersById.values.toList();
    });
  }

  static String _initials(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return words.length == 1
        ? words.first[0].toUpperCase()
        : '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  static bool _sameDisplayName(String first, String second) =>
      first.trim().toLowerCase() == second.trim().toLowerCase();
}
