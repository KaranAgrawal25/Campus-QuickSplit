import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/presentation/providers/database_provider.dart';
import 'package:campus_quicksplit/presentation/screens/root/root_shell.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'rapidly switching root navigation keeps provider dependents safe',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: RootShell()),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 6; index++) {
        await tester.tap(find.text('Groups'));
        await tester.pump();
        await tester.tap(find.text('Activity'));
        await tester.pump();
        await tester.tap(find.text('More'));
        await tester.pump();
        await tester.tap(find.text('Home'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), equals(null));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
