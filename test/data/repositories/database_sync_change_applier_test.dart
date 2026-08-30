import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/repositories/cloud_id_repository.dart';
import 'package:campus_quicksplit/data/repositories/database_sync_change_applier.dart';
import 'package:campus_quicksplit/data/repositories/sync_repository.dart';
import 'package:campus_quicksplit/data/repositories/balance_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a remotely soft-deleted new expense remains deleted locally', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(id: const Value('local-group'), name: 'Trip'),
        );
    await CloudIdRepository(db).link('group', 'local-group', 'cloud-group');

    await DatabaseSyncChangeApplier(db).apply([
      const CloudSyncChange(
        id: 'change-1',
        entityType: 'expense',
        entityId: 'cloud-expense',
        payload: {
          'groupId': 'cloud-group',
          'title': 'Deleted dinner',
          'totalAmountPaise': 10000,
          'category': 'Food',
          'splitType': 'equal',
          'createdAt': '2026-08-01T10:00:00.000Z',
          'isDeleted': true,
        },
      ),
    ]);

    final expense = await db.select(db.expenses).getSingle();
    expect(expense.isDeleted, isTrue);
  });

  test(
    'cloud restore reconstructs members and the authenticated balance',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final users = const [
        ('firebase-karan', 'Karan', 'K'),
        ('member-manav', 'Manav', 'M'),
        ('member-pranshu', 'Pranshu', 'P'),
        ('member-abhay', 'Abhay', 'A'),
      ];
      final changes = <CloudSyncChange>[
        const CloudSyncChange(
          id: 'group',
          entityType: 'group',
          entityId: 'trip',
          payload: {'name': 'Goa Trip', 'createdAt': '2026-08-01T00:00:00Z'},
        ),
        for (final user in users)
          CloudSyncChange(
            id: user.$1,
            entityType: 'user',
            entityId: user.$1,
            payload: {
              'name': user.$2,
              'initials': user.$3,
              'isCurrentUser': user.$1 == 'firebase-karan',
              'createdAt': '2026-08-01T00:00:00Z',
              'updatedAt': '2026-08-01T00:00:00Z',
            },
          ),
        for (final user in users)
          CloudSyncChange(
            id: 'trip-${user.$1}',
            entityType: 'membership',
            entityId: 'trip-${user.$1}',
            payload: {
              'groupId': 'trip',
              'userId': user.$1,
              'joinedAt': '2026-08-01T00:00:00Z',
            },
          ),
        const CloudSyncChange(
          id: 'dinner',
          entityType: 'expense',
          entityId: 'dinner',
          payload: {
            'groupId': 'trip',
            'title': 'Dinner',
            'totalAmountPaise': 40000,
            'category': 'Food',
            'splitType': 'equal',
            'createdAt': '2026-08-02T00:00:00Z',
            'payments': [
              {'userId': 'firebase-karan', 'amountPaidPaise': 40000},
            ],
            'participants': [
              {'userId': 'firebase-karan', 'amountOwedPaise': 10000},
              {'userId': 'member-manav', 'amountOwedPaise': 10000},
              {'userId': 'member-pranshu', 'amountOwedPaise': 10000},
              {'userId': 'member-abhay', 'amountOwedPaise': 10000},
            ],
          },
        ),
      ];

      // Deliberately use an unsafe network order. The applier must resolve
      // dependencies rather than silently losing memberships.
      await DatabaseSyncChangeApplier(db).apply(changes.reversed.toList());

      final current = await (db.select(
        db.users,
      )..where((row) => row.isCurrentUser.equals(true))).getSingle();
      expect(current.name, 'Karan');
      expect(await db.select(db.groupMembers).get(), hasLength(4));
      final summary = await BalanceRepository(db).summary(current.id);
      expect(summary.youAreOwedPaise, 30000);
      expect(summary.youOwePaise, 0);
    },
  );

  test('legacy and Firebase account IDs resolve to one current user',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await DatabaseSyncChangeApplier(db).apply(const [
      CloudSyncChange(
        id: 'old-owner',
        entityType: 'user',
        entityId: 'old-random-owner-id',
        payload: {
          'name': 'Karan',
          'initials': 'K',
          'isCurrentUser': true,
          'createdAt': '2026-08-01T00:00:00Z',
          'updatedAt': '2026-08-01T00:00:00Z',
        },
      ),
      CloudSyncChange(
        id: 'firebase-owner',
        entityType: 'user',
        entityId: 'firebase-uid',
        payload: {
          'name': 'Karan',
          'initials': 'K',
          'isCurrentUser': true,
          'createdAt': '2026-08-01T00:00:00Z',
          'updatedAt': '2026-08-02T00:00:00Z',
        },
      ),
      CloudSyncChange(
        id: 'group',
        entityType: 'group',
        entityId: 'trip',
        payload: {'name': 'Trip', 'createdAt': '2026-08-01T00:00:00Z'},
      ),
      CloudSyncChange(
        id: 'member',
        entityType: 'membership',
        entityId: 'old-member',
        payload: {
          'groupId': 'trip',
          'userId': 'old-random-owner-id',
          'joinedAt': '2026-08-01T00:00:00Z',
        },
      ),
      CloudSyncChange(
        id: 'expense',
        entityType: 'expense',
        entityId: 'dinner',
        payload: {
          'groupId': 'trip',
          'title': 'Dinner',
          'totalAmountPaise': 500000,
          'category': 'Food',
          'splitType': 'equal',
          'createdAt': '2026-08-01T00:00:00Z',
          'payments': [
            {'userId': 'old-random-owner-id', 'amountPaidPaise': 500000},
          ],
          'participants': [
            {'userId': 'firebase-uid', 'amountOwedPaise': 500000},
          ],
        },
      ),
    ]);

    expect(await db.select(db.users).get(), hasLength(1));
    final current = await (db.select(
      db.users,
    )..where((user) => user.isCurrentUser.equals(true))).getSingle();
    expect(await db.select(db.groupMembers).get(), hasLength(1));
    final group = await db.select(db.groups).getSingle();
    final summary = await BalanceRepository(
      db,
    ).groupSummary(groupId: group.id, currentUserId: current.id);
    expect(summary.yourContributionPaise, 500000);
    expect(summary.yourSharePaise, 500000);
  });

  test('cloud restore replays recurring templates and reminder schedules',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await DatabaseSyncChangeApplier(db).apply(const [
      CloudSyncChange(
        id: 'user',
        entityType: 'user',
        entityId: 'cloud-user',
        payload: {
          'name': 'Karan',
          'initials': 'K',
          'isCurrentUser': true,
          'createdAt': '2026-08-01T00:00:00Z',
          'updatedAt': '2026-08-01T00:00:00Z',
        },
      ),
      CloudSyncChange(
        id: 'group',
        entityType: 'group',
        entityId: 'cloud-group',
        payload: {'name': 'Flat', 'createdAt': '2026-08-01T00:00:00Z'},
      ),
      CloudSyncChange(
        id: 'expense',
        entityType: 'expense',
        entityId: 'cloud-expense',
        payload: {
          'groupId': 'cloud-group',
          'title': 'Internet',
          'totalAmountPaise': 50000,
          'category': 'Bills',
          'splitType': 'equal',
          'createdAt': '2026-08-01T00:00:00Z',
        },
      ),
      CloudSyncChange(
        id: 'template',
        entityType: 'recurring_template',
        entityId: 'cloud-template',
        payload: {
          'sourceExpenseId': 'cloud-expense',
          'intervalDays': 30,
          'nextDueAt': '2026-09-01T09:00:00Z',
          'isActive': true,
          'createdAt': '2026-08-01T00:00:00Z',
        },
      ),
      CloudSyncChange(
        id: 'reminder',
        entityType: 'reminder',
        entityId: 'cloud-reminder',
        payload: {
          'title': 'Weekly balance check',
          'body': 'Review your balances.',
          'frequency': 'weekly',
          'hour': 20,
          'minute': 0,
          'weekday': 7,
          'scheduledAt': '2026-08-30T20:00:00Z',
          'nextScheduledAt': '2026-09-06T20:00:00Z',
          'isEnabled': true,
          'createdAt': '2026-08-30T00:00:00Z',
          'updatedAt': '2026-08-30T00:00:00Z',
        },
      ),
    ]);

    final template = await db.select(db.recurringExpenseTemplates).getSingle();
    final reminder = await db.select(db.reminderSchedules).getSingle();
    expect(template.intervalDays, 30);
    expect(reminder.frequency.name, 'weekly');
    expect(reminder.weekday, 7);
  });
}
