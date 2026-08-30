import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/presentation/providers/database_provider.dart';
import 'package:campus_quicksplit/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('accepts a trimmed non-empty name and persists it', (
    tester,
  ) async {
    await _pump(tester, db);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Karan  ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start splitting'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your name'), findsNothing);
    expect((await db.select(db.users).getSingle()).name, 'Karan');
  });

  testWidgets('rejects an empty or whitespace-only name', (tester) async {
    await _pump(tester, db);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Please enter your name'), findsOneWidget);
    expect(await db.select(db.users).get(), isEmpty);
  });
}

Future<void> _pump(WidgetTester tester, AppDatabase db) => tester.pumpWidget(
  ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: OnboardingScreen()),
  ),
);
