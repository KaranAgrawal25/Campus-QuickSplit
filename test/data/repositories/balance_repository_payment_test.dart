import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/repositories/activity_repository.dart';
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
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('me-id'),
            name: 'Me',
            initials: 'M',
            isCurrentUser: const Value(true),
          ),
        );
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('rahul-one-id'),
            name: 'Rahul',
            initials: 'R',
            upiId: const Value('rahul@upi'),
          ),
        );
    // Same name, intentionally distinct stable ID. It must not be paid.
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: const Value('rahul-two-id'),
            name: 'Rahul',
            initials: 'R',
          ),
        );
    await db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(id: const Value('group-id'), name: 'Flat'),
        );
    for (final id in ['me-id', 'rahul-one-id', 'rahul-two-id']) {
      await db
          .into(db.groupMembers)
          .insert(
            GroupMembersCompanion.insert(groupId: 'group-id', userId: id),
          );
    }
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: const Value('expense-id'),
            groupId: 'group-id',
            title: 'Groceries',
            totalAmountPaise: 200000,
            category: 'Food',
          ),
        );
    await db
        .into(db.expensePayments)
        .insert(
          ExpensePaymentsCompanion.insert(
            expenseId: 'expense-id',
            userId: 'rahul-one-id',
            amountPaidPaise: 200000,
          ),
        );
    await db
        .into(db.expenseParticipants)
        .insert(
          ExpenseParticipantsCompanion.insert(
            expenseId: 'expense-id',
            userId: 'me-id',
            amountOwedPaise: 100000,
          ),
        );
    await db
        .into(db.expenseParticipants)
        .insert(
          ExpenseParticipantsCompanion.insert(
            expenseId: 'expense-id',
            userId: 'rahul-one-id',
            amountOwedPaise: 100000,
          ),
        );
  });

  tearDown(() => db.close());

  test(
    'launching/cancelling assistance alone cannot create a settlement',
    () async {
      // The UPI-launch layer does not receive a database repository. Until an
      // explicit confirmation invokes recordSuggestedSettlement, no row exists.
      expect(await balances.watchRecentSettlements().first, isEmpty);
    },
  );

  test(
    'manual confirmation records the suggested stable-ID settlement',
    () async {
      final suggestions = await balances.suggestionsForGroup('group-id');
      expect(suggestions, hasLength(1));
      final suggestion = suggestions.single;
      expect(suggestion.fromUserId, 'me-id');
      expect(suggestion.toUserId, 'rahul-one-id');
      expect(suggestion.amountPaise, 100000);

      await balances.recordSuggestedSettlement(
        groupId: suggestion.groupId,
        fromUserId: suggestion.fromUserId,
        toUserId: suggestion.toUserId,
        amountPaise: suggestion.amountPaise,
      );

      expect((await balances.suggestionsForGroup('group-id')), isEmpty);
      expect((await balances.summary('me-id')).netBalancePaise, 0);
      final activity = await ActivityRepository(db).watchRecent().first;
      expect(activity.where((entry) => entry.settlement != null), hasLength(1));
    },
  );

  test('stale confirmation cannot record the same settlement twice', () async {
    await balances.recordSuggestedSettlement(
      groupId: 'group-id',
      fromUserId: 'me-id',
      toUserId: 'rahul-one-id',
      amountPaise: 100000,
    );
    await expectLater(
      balances.recordSuggestedSettlement(
        groupId: 'group-id',
        fromUserId: 'me-id',
        toUserId: 'rahul-one-id',
        amountPaise: 100000,
      ),
      throwsStateError,
    );
  });
}
