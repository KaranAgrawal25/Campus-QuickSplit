import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/repositories/group_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GroupRepository groups;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    groups = GroupRepository(db);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('owner-id'),
            name: 'Owner',
            initials: 'O',
            isCurrentUser: const Value(true),
          ),
        );
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('member-id'),
            name: 'Member',
            initials: 'M',
          ),
        );
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(id: const Value('group-id'), name: 'Outing'),
        );
    await db
        .into(db.groupMembers)
        .insert(
          GroupMembersCompanion.insert(groupId: 'group-id', userId: 'owner-id'),
        );
  });

  tearDown(() => db.close());

  test('watchGroup refreshes after a member is added', () async {
    expect(
      (await groups.watchGroup('group-id').first)!.members.map(
        (member) => member.id,
      ),
      ['owner-id'],
    );

    final updated = groups.watchGroup('group-id').skip(1).first;
    await groups.addExistingMember('group-id', 'member-id');

    expect((await updated)!.members.map((member) => member.id).toSet(), {
      'owner-id',
      'member-id',
    });
  });
}
