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
    Invites,
    SyncOperations,
    Expenses,
    RecurringExpenseTemplates,
    ReminderSchedules,
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
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE TABLE IF NOT EXISTS cloud_id_mappings ('
        'entity_type TEXT NOT NULL, local_id TEXT NOT NULL, '
        'cloud_id TEXT NOT NULL UNIQUE, '
        'PRIMARY KEY(entity_type, local_id))',
      );
      // Ensure the single settings row always exists so `.watch()`
      // on it never returns an empty stream.
      await into(appSettingsTable).insert(
        const AppSettingsTableCompanion(id: Value(0)),
        mode: InsertMode.insertOrIgnore,
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _addColumnIfMissing(m, groups, groups.isArchived);
        await _addColumnIfMissing(m, settlements, settlements.note);
      }
      if (from < 3) {
        // Some development databases were created with these fields before
        // their user_version was advanced to 3. SQLite has no `ADD COLUMN IF
        // NOT EXISTS`, so inspect the actual schema instead of relying only
        // on the recorded migration version. This preserves the existing
        // table and all of its rows while still upgrading genuine v2 files.
        await _addColumnIfMissing(m, users, users.phoneNumber);
        await _addColumnIfMissing(m, users, users.upiId);
        await _addUpdatedAtIfMissing();
      }
      if (from < 4) await _createTableIfMissing(m, invites);
      if (from < 5) await _createTableIfMissing(m, syncOperations);
      if (from < 6) {
        await _addColumnIfMissing(
          m,
          appSettingsTable,
          appSettingsTable.lockEnabled,
        );
      }
      if (from < 7) {
        await _addColumnIfMissing(m, expenses, expenses.receiptPath);
      }
      if (from < 8) {
        await _addColumnIfMissing(m, expenses, expenses.recurringTemplateId);
        await _createTableIfMissing(m, recurringExpenseTemplates);
      }
      if (from < 9) {
        await _addColumnIfMissing(m, expenses, expenses.recurringOccurrenceKey);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS expenses_recurring_occurrence_key '
          'ON expenses(recurring_occurrence_key) '
          'WHERE recurring_occurrence_key IS NOT NULL',
        );
      }
      if (from < 10) {
        await customStatement(
          'CREATE TABLE IF NOT EXISTS cloud_id_mappings ('
          'entity_type TEXT NOT NULL, local_id TEXT NOT NULL, '
          'cloud_id TEXT NOT NULL UNIQUE, '
          'PRIMARY KEY(entity_type, local_id))',
        );
      }
      if (from < 11) {
        await _addColumnIfMissing(m, users, users.email);
      }
      if (from < 12) await _createTableIfMissing(m, reminderSchedules);
    },
  );

  /// Makes historical migrations resilient to databases whose SQLite
  /// `user_version` lagged behind a schema change during development. We only
  /// skip the specific DDL operation when SQLite confirms it already exists;
  /// missing tables and unrelated schema errors still fail normally.
  Future<void> _addColumnIfMissing(
    Migrator migrator,
    TableInfo<Table, Object?> table,
    GeneratedColumn column,
  ) async {
    if (!await _columnExists(table.actualTableName, column.$name)) {
      await migrator.addColumn(table, column);
    }
  }

  Future<void> _createTableIfMissing(
    Migrator migrator,
    TableInfo<Table, Object?> table,
  ) async {
    if (!await _tableExists(table.actualTableName)) {
      await migrator.createTable(table);
    }
  }

  Future<void> _addUpdatedAtIfMissing() async {
    if (await _columnExists(users.actualTableName, users.updatedAt.$name)) {
      return;
    }

    // SQLite rejects `ALTER TABLE ... ADD COLUMN` when the default is a
    // non-constant expression such as Drift's `currentDateAndTime`. Add a
    // safe constant default, then immediately backfill existing records. New
    // user writes always provide their timestamp explicitly (see the user and
    // group repositories), so the sentinel is never exposed to the app.
    await customStatement(
      'ALTER TABLE "users" ADD COLUMN "updated_at" INTEGER NOT NULL DEFAULT 0',
    );
    await customStatement(
      'UPDATE "users" SET "updated_at" = '
      "CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER) "
      'WHERE "updated_at" = 0',
    );
  }

  Future<bool> _columnExists(String tableName, String columnName) async {
    final columns = await customSelect('PRAGMA table_info($tableName)').get();
    return columns.any((column) => column.read<String>('name') == columnName);
  }

  Future<bool> _tableExists(String tableName) async {
    final tables = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable<String>(tableName)],
    ).get();
    return tables.isNotEmpty;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'campus_quicksplit.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
