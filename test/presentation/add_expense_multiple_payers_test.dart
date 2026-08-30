import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/presentation/providers/database_provider.dart';
import 'package:campus_quicksplit/presentation/screens/expenses/add_expense_screen.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a contribution amount for each selected payer', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedGroup(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: AddExpenseScreen(groupId: 'group-id')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Multiple people paid'));
    await tester.pumpAndSettle();

    expect(
      find.text('Payer amounts must add up exactly to the expense total.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Paid (₹)'), findsNWidgets(2));
    expect(tester.takeException(), equals(null));
  });

  testWidgets('keeps every split option readable at narrow phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedGroup(db);

    for (final width in [360.0, 375.0, 390.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: AddExpenseScreen(groupId: 'group-id')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Equal'), findsOneWidget);
      expect(find.text('Amount'), findsWidgets);
      expect(find.text('Ratio'), findsOneWidget);
      expect(find.text('Percent'), findsOneWidget);
      expect(tester.takeException(), equals(null));
    }
  });
}

Future<void> _seedGroup(AppDatabase db) async {
  for (final user in [('me', 'Karan', true), ('other', 'Abhay', false)]) {
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(user.$1),
            name: user.$2,
            initials: user.$2.substring(0, 1),
            isCurrentUser: Value(user.$3),
          ),
        );
  }
  await db
      .into(db.groups)
      .insert(
        GroupsCompanion.insert(id: const Value('group-id'), name: 'Outing'),
      );
  for (final userId in ['me', 'other']) {
    await db
        .into(db.groupMembers)
        .insert(
          GroupMembersCompanion.insert(groupId: 'group-id', userId: userId),
        );
  }
}
