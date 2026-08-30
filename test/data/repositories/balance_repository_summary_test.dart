import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/database/tables.dart';
import 'package:campus_quicksplit/data/repositories/balance_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BalanceRepository balances;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    balances = BalanceRepository(db);
    await _insertUser(db, 'me');
    await _insertUser(db, 'other');
  });

  tearDown(() => db.close());

  test(
    'reports only gross receivables when others owe the current user',
    () async {
      await _addTwoPersonExpense(
        db,
        groupId: 'receivable-group',
        expenseId: 'receivable-expense',
        payerId: 'me',
        totalPaise: 20001,
      );

      final summary = await balances.summary('me');

      expect(summary.youAreOwedPaise, 10001);
      expect(summary.youOwePaise, 0);
      expect(summary.netBalancePaise, 10001);
    },
  );

  test('reports only gross payables when the current user owes', () async {
    await _addTwoPersonExpense(
      db,
      groupId: 'payable-group',
      expenseId: 'payable-expense',
      payerId: 'other',
      totalPaise: 25000,
    );

    final summary = await balances.summary('me');

    expect(summary.youAreOwedPaise, 0);
    expect(summary.youOwePaise, 12500);
    expect(summary.netBalancePaise, -12500);
  });

  test(
    'keeps gross values separate across groups and nets in exact paise',
    () async {
      // ₹8,333.32 paid by the current user and split equally leaves the other
      // member owing ₹4,166.66. In another group, the current user owes ₹125.
      await _addTwoPersonExpense(
        db,
        groupId: 'goa-trip',
        expenseId: 'goa-expense',
        payerId: 'me',
        totalPaise: 833332,
      );
      await _addTwoPersonExpense(
        db,
        groupId: 'dinner',
        expenseId: 'dinner-expense',
        payerId: 'other',
        totalPaise: 25000,
      );

      final summary = await balances.summary('me');

      expect(summary.youAreOwedPaise, 416666);
      expect(summary.youOwePaise, 12500);
      expect(summary.netBalancePaise, 404166);
    },
  );

  test('reports zero amounts after a group is fully settled', () async {
    await _addTwoPersonExpense(
      db,
      groupId: 'settled-group',
      expenseId: 'settled-expense',
      payerId: 'other',
      totalPaise: 25000,
    );
    await db
        .into(db.settlements)
        .insert(
          SettlementsCompanion.insert(
            id: const Value('settlement-id'),
            groupId: 'settled-group',
            fromUserId: 'me',
            toUserId: 'other',
            amountPaise: 12500,
            status: const Value(SettlementStatus.completed),
          ),
        );

    final summary = await balances.summary('me');

    expect(summary.youAreOwedPaise, 0);
    expect(summary.youOwePaise, 0);
    expect(summary.netBalancePaise, 0);
  });

  test(
    'does not include archived groups in the active dashboard summary',
    () async {
      await _addTwoPersonExpense(
        db,
        groupId: 'archived-group',
        expenseId: 'archived-expense',
        payerId: 'me',
        totalPaise: 25000,
      );
      await (db.update(db.groups)
            ..where((group) => group.id.equals('archived-group')))
          .write(const GroupsCompanion(isArchived: Value(true)));

      final summary = await balances.summary('me');

      expect(summary.youAreOwedPaise, 0);
      expect(summary.youOwePaise, 0);
      expect(summary.netBalancePaise, 0);
    },
  );
}

Future<void> _insertUser(AppDatabase db, String id) => db
    .into(db.users)
    .insert(
      UsersCompanion.insert(
        id: Value(id),
        name: id,
        initials: id.substring(0, 1).toUpperCase(),
        isCurrentUser: Value(id == 'me'),
      ),
    );

Future<void> _addTwoPersonExpense(
  AppDatabase db, {
  required String groupId,
  required String expenseId,
  required String payerId,
  required int totalPaise,
}) async {
  await db
      .into(db.groups)
      .insert(GroupsCompanion.insert(id: Value(groupId), name: groupId));
  for (final userId in ['me', 'other']) {
    await db
        .into(db.groupMembers)
        .insert(GroupMembersCompanion.insert(groupId: groupId, userId: userId));
  }
  await db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: Value(expenseId),
          groupId: groupId,
          title: expenseId,
          totalAmountPaise: totalPaise,
          category: 'Food',
        ),
      );
  await db
      .into(db.expensePayments)
      .insert(
        ExpensePaymentsCompanion.insert(
          expenseId: expenseId,
          userId: payerId,
          amountPaidPaise: totalPaise,
        ),
      );
  final currentUserShare = totalPaise ~/ 2;
  final otherUserShare = totalPaise - currentUserShare;
  await db
      .into(db.expenseParticipants)
      .insert(
        ExpenseParticipantsCompanion.insert(
          expenseId: expenseId,
          userId: 'me',
          amountOwedPaise: currentUserShare,
        ),
      );
  await db
      .into(db.expenseParticipants)
      .insert(
        ExpenseParticipantsCompanion.insert(
          expenseId: expenseId,
          userId: 'other',
          amountOwedPaise: otherUserShare,
        ),
      );
}
