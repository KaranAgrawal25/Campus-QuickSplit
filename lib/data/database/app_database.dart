import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Groups,
    GroupMembers,
    Expenses,
    ExpenseParticipants,
    ExpensePayments,
    Settlements,
    AppSettingsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Used by tests to inject an in-memory database instead of a file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Ensure the single settings row always exists so `.watch()`
      // on it never returns an empty stream.
      await into(appSettingsTable).insert(
        const AppSettingsTableCompanion(id: Value(0)),
        mode: InsertMode.insertOrIgnore,
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(groups, groups.isArchived);
        await m.addColumn(settlements, settlements.note);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'campus_quicksplit.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
