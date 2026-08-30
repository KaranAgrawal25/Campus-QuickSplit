import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/presentation/providers/database_provider.dart';
import 'package:campus_quicksplit/presentation/screens/groups/group_detail_screen.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'opening the Add member dialog keeps inherited dependents valid',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedGroup(db);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            home: GroupDetailScreen(groupId: 'group-id'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();

      expect(find.text('Add member'), findsOneWidget);
      expect(tester.takeException(), equals(null));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('swiping an expense soft-deletes it from the persisted list', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedGroup(db);
    await _seedExpense(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: GroupDetailScreen(groupId: 'group-id')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    final expenseTile = find.byKey(const ValueKey('expense-expense-id'));
    await tester.scrollUntilVisible(
      expenseTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      expenseTile,
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    final expense = await (db.select(
      db.expenses,
    )..where((row) => row.id.equals('expense-id'))).getSingle();
    expect(expense.isDeleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Future<void> _seedGroup(AppDatabase db) async {
  await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: const Value('me'),
          name: 'Karan',
          initials: 'K',
          isCurrentUser: const Value(true),
        ),
      );
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(id: const Value('group-id'), name: 'Outing'),
      );
  await db
      .into(db.groupMembers)
      .insert(GroupMembersCompanion.insert(groupId: 'group-id', userId: 'me'));
}

Future<void> _seedExpense(AppDatabase db) async {
  await db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: const Value('expense-id'),
          groupId: 'group-id',
          title: 'Dinner',
          totalAmountPaise: 10000,
          category: 'Food',
        ),
      );
  await db
      .into(db.expensePayments)
      .insert(
        ExpensePaymentsCompanion.insert(
          expenseId: 'expense-id',
          userId: 'me',
          amountPaidPaise: 10000,
        ),
      );
  await db
      .into(db.expenseParticipants)
      .insert(
        ExpenseParticipantsCompanion.insert(
          expenseId: 'expense-id',
          userId: 'me',
          amountOwedPaise: 10000,
        ),
      );
}
