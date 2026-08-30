import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/repositories/analytics_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'personal analytics counts only money paid by the current user',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('karan'),
              name: 'Karan',
              initials: 'K',
              isCurrentUser: const Value(true),
            ),
          );
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('manav'),
              name: 'Manav',
              initials: 'M',
            ),
          );
      await db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(id: const Value('trip'), name: 'Trip'),
          );
      for (final id in ['karan', 'manav']) {
        await db
            .into(db.groupMembers)
            .insert(GroupMembersCompanion.insert(groupId: 'trip', userId: id));
      }
      for (final expense in [('karan-paid', 200000), ('manav-paid', 300000)]) {
        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: Value(expense.$1),
                groupId: 'trip',
                title: expense.$1,
                totalAmountPaise: expense.$2,
                category: 'Food',
              ),
            );
        await db
            .into(db.expensePayments)
            .insert(
              ExpensePaymentsCompanion.insert(
                expenseId: expense.$1,
                userId: expense.$1 == 'karan-paid' ? 'karan' : 'manav',
                amountPaidPaise: expense.$2,
              ),
            );
        for (final id in ['karan', 'manav']) {
          await db
              .into(db.expenseParticipants)
              .insert(
                ExpenseParticipantsCompanion.insert(
                  expenseId: expense.$1,
                  userId: id,
                  amountOwedPaise: expense.$2 ~/ 2,
                ),
              );
        }
      }

      final summary = await AnalyticsRepository(db).summary('karan');

      expect(summary.personalContributionPaise, 200000);
      expect(summary.personalSharePaise, 250000);
      expect(summary.totalSpentPaise, 500000);
      expect(summary.categoryTotals['Food'], 200000);
    },
  );
}
