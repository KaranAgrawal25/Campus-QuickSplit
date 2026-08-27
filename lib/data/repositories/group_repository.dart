import 'package:drift/drift.dart';

import '../database/app_database.dart';

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

  Stream<GroupWithMembers?> watchGroup(String groupId) async* {
    await for (final group in (_db.select(
      _db.groups,
    )..where((g) => g.id.equals(groupId))).watchSingleOrNull()) {
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
        final user = await _db
            .into(_db.users)
            .insertReturning(
              UsersCompanion.insert(
                name: memberName,
                initials: _initials(memberName),
              ),
            );
        await _db
            .into(_db.groupMembers)
            .insert(
              GroupMembersCompanion.insert(groupId: group.id, userId: user.id),
            );
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
  }

  Future<void> archive(String groupId) =>
      (_db.update(_db.groups)..where((g) => g.id.equals(groupId))).write(
        const GroupsCompanion(isArchived: Value(true)),
      );

  Future<User> addMember(String groupId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Member name is required');
    return _db.transaction(() async {
      final user = await _db
          .into(_db.users)
          .insertReturning(
            UsersCompanion.insert(name: trimmed, initials: _initials(trimmed)),
          );
      await _db
          .into(_db.groupMembers)
          .insert(
            GroupMembersCompanion.insert(groupId: groupId, userId: user.id),
          );
      return user;
    });
  }

  Future<void> removeMember(String groupId, String userId) async {
    final expenses = await (_db.select(
      _db.expenseParticipants,
    )..where((p) => p.userId.equals(userId))).get();
    if (expenses.isNotEmpty) {
      throw StateError('This member has expense history and cannot be removed');
    }
    await (_db.delete(
      _db.groupMembers,
    )..where((m) => m.groupId.equals(groupId) & m.userId.equals(userId))).go();
  }

  Future<List<User>> members(String groupId) => _membersFor(groupId);

  Future<List<User>> _membersFor(String groupId) {
    final query = _db.select(_db.users).join([
      innerJoin(
        _db.groupMembers,
        _db.groupMembers.userId.equalsExp(_db.users.id),
      ),
    ])..where(_db.groupMembers.groupId.equals(groupId));
    return query.get().then(
      (rows) => rows.map((row) => row.readTable(_db.users)).toList(),
    );
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
}
