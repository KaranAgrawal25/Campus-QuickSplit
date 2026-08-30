import 'dart:io';

import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fresh database creates the complete version 12 schema', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      12,
    );
    for (final table in [
      'users',
      'invites',
      'sync_operations',
      'cloud_id_mappings',
      'reminder_schedules',
    ]) {
      expect(
        await _tableExists(db, table),
        isTrue,
        reason: '$table is missing',
      );
    }
  });

  test(
    'upgrades a version-2 database whose later schema already exists',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'campus_quicksplit_migration_test_',
      );
      final file = File('${directory.path}/database.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));

      await _seedCompleteSchema(db);
      // This represents the development-era inconsistency behind the startup
      // crash: SQLite still reports v2 although the v3-v5 DDL is already
      // present and contains real data.
      await db.customStatement('PRAGMA user_version = 2');
      await db.close();

      db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });

      expect((await db.select(db.users).getSingle()).id, 'user-id');
      final user = await db.select(db.users).getSingle();
      expect(user.phoneNumber, '+919876543210');
      expect(user.upiId, 'owner@upi');
      expect(user.updatedAt, isNot(equals(null)));

      expect((await db.select(db.groups).getSingle()).id, 'group-id');
      expect((await db.select(db.groupMembers).getSingle()).userId, 'user-id');
      expect((await db.select(db.expenses).getSingle()).id, 'expense-id');
      expect(
        (await db.select(db.expenseParticipants).getSingle()).amountOwedPaise,
        12500,
      );
      expect(
        (await db.select(db.expensePayments).getSingle()).amountPaidPaise,
        12500,
      );
      expect((await db.select(db.settlements).getSingle()).id, 'settlement-id');
      expect((await db.select(db.invites).getSingle()).id, 'invite-id');
      expect((await db.select(db.syncOperations).getSingle()).id, 'sync-id');
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        12,
      );
      expect(await _tableExists(db, 'cloud_id_mappings'), isTrue);
    },
  );

  test(
    'upgrades a genuine version-2 users table without profile fields',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'campus_quicksplit_legacy_migration_test_',
      );
      final file = File('${directory.path}/database.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));

      // Use the current schema only to initialize the file, then replace the
      // empty users table with its v2 shape. This isolates the migration path
      // where profile columns have never existed.
      await db.customStatement('DROP TABLE users');
      await db.customStatement('''
      CREATE TABLE users (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        initials TEXT NOT NULL,
        is_current_user INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
      await db.customStatement(
        '''INSERT INTO users (id, name, initials, is_current_user, created_at)
         VALUES ('legacy-user-id', 'Legacy User', 'LU', 1, 0)''',
      );
      await db.customStatement('PRAGMA user_version = 2');
      await db.close();

      db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });

      final user = await db.select(db.users).getSingle();
      expect(user.id, 'legacy-user-id');
      expect(user.phoneNumber, equals(null));
      expect(user.upiId, equals(null));
      expect(user.email, equals(null));
      expect(user.updatedAt, isNot(equals(null)));
    },
  );
}

Future<bool> _tableExists(AppDatabase db, String tableName) async {
  return (await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [Variable<String>(tableName)],
          )
          .get())
      .isNotEmpty;
}

Future<void> _seedCompleteSchema(AppDatabase db) async {
  await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: const Value('user-id'),
          name: 'Owner',
          initials: 'O',
          isCurrentUser: const Value(true),
          phoneNumber: const Value('+919876543210'),
          upiId: const Value('owner@upi'),
        ),
      );
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(id: const Value('group-id'), name: 'Trip'),
      );
  await db
      .into(db.groupMembers)
      .insert(
        GroupMembersCompanion.insert(groupId: 'group-id', userId: 'user-id'),
      );
  await db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: const Value('expense-id'),
          groupId: 'group-id',
          title: 'Lunch',
          totalAmountPaise: 12500,
          category: 'Food',
        ),
      );
  await db
      .into(db.expenseParticipants)
      .insert(
        ExpenseParticipantsCompanion.insert(
          expenseId: 'expense-id',
          userId: 'user-id',
          amountOwedPaise: 12500,
        ),
      );
  await db
      .into(db.expensePayments)
      .insert(
        ExpensePaymentsCompanion.insert(
          expenseId: 'expense-id',
          userId: 'user-id',
          amountPaidPaise: 12500,
        ),
      );
  await db
      .into(db.settlements)
      .insert(
        SettlementsCompanion.insert(
          id: const Value('settlement-id'),
          groupId: 'group-id',
          fromUserId: 'user-id',
          toUserId: 'user-id',
          amountPaise: 12500,
        ),
      );
  await db
      .into(db.invites)
      .insert(
        InvitesCompanion.insert(
          id: const Value('invite-id'),
          groupId: 'group-id',
          token: 'invite-token',
        ),
      );
  await db
      .into(db.syncOperations)
      .insert(
        SyncOperationsCompanion.insert(
          id: const Value('sync-id'),
          operationKey: 'upsert:user:user-id',
          entityType: 'user',
          entityId: 'user-id',
          payloadJson: '{"id":"user-id"}',
        ),
      );
}
