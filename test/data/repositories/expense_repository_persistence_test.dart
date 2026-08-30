import 'dart:io';

import 'package:campus_quicksplit/core/finance/split_engine.dart';
import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/database/tables.dart';
import 'package:campus_quicksplit/data/repositories/balance_repository.dart';
import 'package:campus_quicksplit/data/repositories/expense_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense persists exactly once across a database restart', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final expenseId = await fixture.expenses.create(_draft(totalPaise: 10000));
    await fixture.restart();

    final expenses = await fixture.expenses
        .watchRecent(groupId: 'group-id')
        .first;
    expect(expenses.map((expense) => expense.id), [expenseId]);
    expect(expenses.single.totalAmountPaise, 10000);
    expect((await fixture.expenses.details(expenseId))!.shares, hasLength(2));
  });

  test(
    'a soft-deleted expense remains stored but no longer affects balances',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final expenseId = await fixture.expenses.create(
        _draft(totalPaise: 10000),
      );
      expect((await fixture.balances.summary('me')).youAreOwedPaise, 5000);

      await fixture.expenses.delete(expenseId);
      await fixture.restart();

      expect(
        await fixture.expenses.watchRecent(groupId: 'group-id').first,
        isEmpty,
      );
      final balance = await fixture.balances.summary('me');
      expect(balance.youAreOwedPaise, 0);
      expect(balance.youOwePaise, 0);
      expect(balance.netBalancePaise, 0);
      expect(
        (await fixture.db.select(fixture.db.expenses).getSingle()).isDeleted,
        isTrue,
      );
    },
  );

  test(
    'editing replaces financial rows exactly once across a restart',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final expenseId = await fixture.expenses.create(
        _draft(totalPaise: 10000),
      );
      await fixture.expenses.update(
        expenseId,
        ExpenseDraft(
          groupId: 'group-id',
          title: 'Edited dinner',
          totalAmountPaise: 999,
          payerId: 'me',
          payments: const [
            ExpensePaymentDraft(userId: 'me', amountPaidPaise: 499),
            ExpensePaymentDraft(userId: 'other', amountPaidPaise: 500),
          ],
          participants: const [
            SplitShare(userId: 'me', amountPaise: 333),
            SplitShare(userId: 'other', amountPaise: 666),
          ],
          splitType: SplitTypeDb.specificAmount,
          date: DateTime.utc(2026, 8, 28, 12),
        ),
      );
      await fixture.restart();

      final expenses = await fixture.expenses
          .watchRecent(groupId: 'group-id')
          .first;
      expect(expenses, hasLength(1));
      expect(expenses.single.id, expenseId);
      expect(expenses.single.title, 'Edited dinner');
      expect(expenses.single.totalAmountPaise, 999);
      final details = (await fixture.expenses.details(expenseId))!;
      expect(details.payments, hasLength(2));
      expect(
        details.payments.fold<int>(
          0,
          (sum, item) => sum + item.payment.amountPaidPaise,
        ),
        999,
      );
      expect(details.shares, hasLength(2));
      expect(
        details.shares.fold<int>(
          0,
          (sum, item) => sum + item.share.amountOwedPaise,
        ),
        999,
      );
    },
  );
}

ExpenseDraft _draft({required int totalPaise}) => ExpenseDraft(
  groupId: 'group-id',
  title: 'Dinner',
  totalAmountPaise: totalPaise,
  payerId: 'me',
  participants: SplitEngine.equal(
    totalPaise: totalPaise,
    userIds: const ['me', 'other'],
  ),
  splitType: SplitTypeDb.equal,
  date: DateTime.utc(2026, 8, 28),
);

class _Fixture {
  _Fixture._(this.directory, this.file, this.db);

  final Directory directory;
  final File file;
  AppDatabase db;

  ExpenseRepository get expenses => ExpenseRepository(db);
  BalanceRepository get balances => BalanceRepository(db);

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'campus_quicksplit_expense_persistence_',
    );
    final fixture = _Fixture._(
      directory,
      File('${directory.path}/database.sqlite'),
      AppDatabase.forTesting(
        NativeDatabase(File('${directory.path}/database.sqlite')),
      ),
    );
    await fixture.db
        .into(fixture.db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('me'),
            name: 'Me',
            initials: 'M',
            isCurrentUser: const Value(true),
          ),
        );
    await fixture.db
        .into(fixture.db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('other'),
            name: 'Other',
            initials: 'O',
          ),
        );
    await fixture.db
        .into(fixture.db.groups)
        .insert(
          GroupsCompanion.insert(id: const Value('group-id'), name: 'Trip'),
        );
    for (final userId in ['me', 'other']) {
      await fixture.db
          .into(fixture.db.groupMembers)
          .insert(
            GroupMembersCompanion.insert(groupId: 'group-id', userId: userId),
          );
    }
    return fixture;
  }

  Future<void> restart() async {
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
  }

  Future<void> dispose() async {
    await db.close();
    await directory.delete(recursive: true);
  }
}
