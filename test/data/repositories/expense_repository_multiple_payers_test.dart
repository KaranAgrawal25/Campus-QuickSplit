import 'package:campus_quicksplit/core/finance/split_engine.dart';
import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/database/tables.dart';
import 'package:campus_quicksplit/data/repositories/expense_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'persists multiple payer amounts exactly once and exactly totals expense',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seed(db);

      final id = await ExpenseRepository(db).create(
        ExpenseDraft(
          groupId: 'group-id',
          title: 'Restaurant',
          totalAmountPaise: 400000,
          payerId: 'karan',
          payments: const [
            ExpensePaymentDraft(userId: 'karan', amountPaidPaise: 200000),
            ExpensePaymentDraft(userId: 'abhay', amountPaidPaise: 100000),
            ExpensePaymentDraft(userId: 'manav', amountPaidPaise: 100000),
          ],
          participants: SplitEngine.equal(
            totalPaise: 400000,
            userIds: const ['karan', 'abhay', 'manav', 'pranshu'],
          ),
          splitType: SplitTypeDb.equal,
          date: DateTime.utc(2026, 8, 28),
        ),
      );

      final payments = await (db.select(
        db.expensePayments,
      )..where((payment) => payment.expenseId.equals(id))).get();
      expect(payments, hasLength(3));
      expect(
        payments.fold<int>(0, (sum, payment) => sum + payment.amountPaidPaise),
        400000,
      );
      final details = await ExpenseRepository(db).details(id);
      expect(details!.payments, hasLength(3));
      expect(
        details.payments.map((item) => item.user.id),
        containsAll(['karan', 'abhay', 'manav']),
      );
    },
  );
}

Future<void> _seed(AppDatabase db) async {
  for (final id in ['karan', 'abhay', 'manav', 'pranshu']) {
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(id),
            name: id,
            initials: id.substring(0, 1).toUpperCase(),
            isCurrentUser: Value(id == 'karan'),
          ),
        );
  }
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(id: const Value('group-id'), name: 'Outing'),
      );
  for (final id in ['karan', 'abhay', 'manav', 'pranshu']) {
    await db
        .into(db.groupMembers)
        .insert(GroupMembersCompanion.insert(groupId: 'group-id', userId: id));
  }
}
