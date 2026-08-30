import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/tables.dart';

class BackupPreview {
  const BackupPreview({
    required this.payload,
    required this.userCount,
    required this.groupCount,
    required this.expenseCount,
  });

  final Map<String, Object?> payload;
  final int userCount;
  final int groupCount;
  final int expenseCount;
}

/// Versioned, portable, data-only snapshot. Receipt images are intentionally
/// excluded: they can be large and may contain sensitive material. The backup
/// records neither device credentials nor biometric data.
class BackupRepository {
  BackupRepository(this._db);
  final AppDatabase _db;

  Future<File> createBackup() async {
    Map<String, Object?> date(DateTime value) => {
      'utc': value.toUtc().toIso8601String(),
    };
    final data = <String, Object?>{
      'format': 'campus-quicksplit-backup',
      'schemaVersion': 1,
      // Kept for backwards compatibility with previews produced by the first
      // public build.
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'attachments': {'receiptsIncluded': false},
      'cloudIdMappings':
          (await _db
                  .customSelect(
                    'SELECT entity_type, local_id, cloud_id FROM cloud_id_mappings',
                  )
                  .get())
              .map(
                (row) => {
                  'entityType': row.read<String>('entity_type'),
                  'localId': row.read<String>('local_id'),
                  'cloudId': row.read<String>('cloud_id'),
                },
              )
              .toList(),
      'users': (await _db.select(_db.users).get())
          .map(
            (user) => {
              'id': user.id,
              'name': user.name,
              'initials': user.initials,
              'isCurrentUser': user.isCurrentUser,
              'phoneNumber': user.phoneNumber,
              'email': user.email,
              'upiId': user.upiId,
              'createdAt': date(user.createdAt),
              'updatedAt': date(user.updatedAt),
            },
          )
          .toList(),
      'groups': (await _db.select(_db.groups).get())
          .map(
            (group) => {
              'id': group.id,
              'name': group.name,
              'isArchived': group.isArchived,
              'createdAt': date(group.createdAt),
            },
          )
          .toList(),
      'groupMembers': (await _db.select(_db.groupMembers).get())
          .map(
            (member) => {
              'groupId': member.groupId,
              'userId': member.userId,
              'joinedAt': date(member.joinedAt),
            },
          )
          .toList(),
      'expenses': (await _db.select(_db.expenses).get())
          .map(
            (expense) => {
              'id': expense.id,
              'groupId': expense.groupId,
              'title': expense.title,
              'description': expense.description,
              'totalAmountPaise': expense.totalAmountPaise,
              'category': expense.category,
              'splitType': expense.splitType.name,
              'createdAt': date(expense.createdAt),
              'isDeleted': expense.isDeleted,
              'recurringTemplateId': expense.recurringTemplateId,
              'recurringOccurrenceKey': expense.recurringOccurrenceKey,
            },
          )
          .toList(),
      'recurringExpenseTemplates':
          (await _db.select(_db.recurringExpenseTemplates).get())
              .map(
                (template) => {
                  'id': template.id,
                  'sourceExpenseId': template.sourceExpenseId,
                  'intervalDays': template.intervalDays,
                  'nextDueAt': date(template.nextDueAt),
                  'isActive': template.isActive,
                  'createdAt': date(template.createdAt),
                },
              )
              .toList(),
      'settings': (await _db.select(_db.appSettingsTable).get())
          .map(
            (settings) => {
              'themeMode': settings.themeMode,
              'onboardingComplete': settings.onboardingComplete,
              'lockEnabled': settings.lockEnabled,
            },
          )
          .toList(),
      'reminderSchedules': (await _db.select(_db.reminderSchedules).get())
          .map(
            (reminder) => {
              'id': reminder.id,
              'title': reminder.title,
              'body': reminder.body,
              'frequency': reminder.frequency.name,
              'hour': reminder.hour,
              'minute': reminder.minute,
              'weekday': reminder.weekday,
              'dayOfMonth': reminder.dayOfMonth,
              'scheduledAt': date(reminder.scheduledAt),
              'nextScheduledAt': date(reminder.nextScheduledAt),
              'isEnabled': reminder.isEnabled,
              'createdAt': date(reminder.createdAt),
              'updatedAt': date(reminder.updatedAt),
            },
          )
          .toList(),
      'expenseParticipants': (await _db.select(_db.expenseParticipants).get())
          .map(
            (share) => {
              'expenseId': share.expenseId,
              'userId': share.userId,
              'amountOwedPaise': share.amountOwedPaise,
              'ratio': share.ratio,
            },
          )
          .toList(),
      'expensePayments': (await _db.select(_db.expensePayments).get())
          .map(
            (payment) => {
              'expenseId': payment.expenseId,
              'userId': payment.userId,
              'amountPaidPaise': payment.amountPaidPaise,
            },
          )
          .toList(),
      'settlements': (await _db.select(_db.settlements).get())
          .map(
            (settlement) => {
              'id': settlement.id,
              'groupId': settlement.groupId,
              'fromUserId': settlement.fromUserId,
              'toUserId': settlement.toUserId,
              'amountPaise': settlement.amountPaise,
              'note': settlement.note,
              'status': settlement.status.name,
              'createdAt': date(settlement.createdAt),
            },
          )
          .toList(),
    };
    final root = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final directory = await Directory(
      p.join(root!.path, 'Campus QuickSplit', 'Backups'),
    ).create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final file = File(
      p.join(directory.path, 'campus-quicksplit-backup-$timestamp.json'),
    );
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  /// Validates a backup before presenting its contents to the user. Restore is
  /// purposefully allowed only into an empty database: there is no hidden
  /// overwrite or heuristic merge of financial records.
  Future<BackupPreview> inspectBackup(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('Invalid backup file');
    final payload = Map<String, Object?>.from(decoded);
    if (payload['format'] != 'campus-quicksplit-backup' ||
        (payload['schemaVersion'] ?? payload['version']) != 1) {
      throw const FormatException(
        'This is not a supported Campus QuickSplit backup',
      );
    }
    List<Object?> list(String key) => payload[key] is List
        ? List<Object?>.from(payload[key]! as List)
        : throw FormatException('Backup is missing $key');
    return BackupPreview(
      payload: payload,
      userCount: list('users').length,
      groupCount: list('groups').length,
      expenseCount: list('expenses').length,
    );
  }

  Future<void> restoreIntoEmptyDatabase(BackupPreview preview) async {
    final hasData =
        (await _db.select(_db.users).get()).isNotEmpty ||
        (await _db.select(_db.groups).get()).isNotEmpty ||
        (await _db.select(_db.expenses).get()).isNotEmpty;
    if (hasData) {
      throw StateError(
        'For safety, restore is available only before creating data on this device',
      );
    }
    final payload = preview.payload;
    List<Map<String, Object?>> records(String key) => List<Object?>.from(
      payload[key]! as List,
    ).map((value) => Map<String, Object?>.from(value! as Map)).toList();
    List<Map<String, Object?>> optionalRecords(String key) =>
        payload[key] is List
        ? List<Object?>.from(
            payload[key]! as List,
          ).map((value) => Map<String, Object?>.from(value! as Map)).toList()
        : const [];
    DateTime time(Object? value) {
      final map = Map<String, Object?>.from(value! as Map);
      return DateTime.parse(map['utc']! as String).toLocal();
    }

    await _db.transaction(() async {
      await _db.batch((batch) {
        batch.insertAll(
          _db.users,
          records('users').map(
            (row) => UsersCompanion.insert(
              id: Value(row['id']! as String),
              name: row['name']! as String,
              initials: row['initials']! as String,
              isCurrentUser: Value(row['isCurrentUser']! as bool),
              phoneNumber: Value(row['phoneNumber'] as String?),
              email: Value(row['email'] as String?),
              upiId: Value(row['upiId'] as String?),
              createdAt: Value(time(row['createdAt'])),
              updatedAt: Value(time(row['updatedAt'])),
            ),
          ),
        );
        batch.insertAll(
          _db.groups,
          records('groups').map(
            (row) => GroupsCompanion.insert(
              id: Value(row['id']! as String),
              name: row['name']! as String,
              isArchived: Value(row['isArchived']! as bool),
              createdAt: Value(time(row['createdAt'])),
            ),
          ),
        );
        batch.insertAll(
          _db.groupMembers,
          records('groupMembers').map(
            (row) => GroupMembersCompanion.insert(
              groupId: row['groupId']! as String,
              userId: row['userId']! as String,
              joinedAt: Value(time(row['joinedAt'])),
            ),
          ),
        );
        batch.insertAll(
          _db.expenses,
          records('expenses').map(
            (row) => ExpensesCompanion.insert(
              id: Value(row['id']! as String),
              groupId: row['groupId']! as String,
              title: row['title']! as String,
              description: Value(row['description'] as String?),
              totalAmountPaise: row['totalAmountPaise']! as int,
              category: row['category']! as String,
              splitType: Value(
                SplitTypeDb.values.byName(row['splitType']! as String),
              ),
              createdAt: Value(time(row['createdAt'])),
              isDeleted: Value(row['isDeleted']! as bool),
              recurringTemplateId: Value(row['recurringTemplateId'] as String?),
              recurringOccurrenceKey: Value(
                row['recurringOccurrenceKey'] as String?,
              ),
            ),
          ),
        );
        batch.insertAll(
          _db.recurringExpenseTemplates,
          optionalRecords('recurringExpenseTemplates').map(
            (row) => RecurringExpenseTemplatesCompanion.insert(
              id: Value(row['id']! as String),
              sourceExpenseId: row['sourceExpenseId']! as String,
              intervalDays: row['intervalDays']! as int,
              nextDueAt: time(row['nextDueAt']),
              isActive: Value(row['isActive']! as bool),
              createdAt: Value(time(row['createdAt'])),
            ),
          ),
        );
        batch.insertAll(
          _db.reminderSchedules,
          optionalRecords('reminderSchedules').map(
            (row) => ReminderSchedulesCompanion.insert(
              id: Value(row['id']! as String),
              title: row['title']! as String,
              body: row['body']! as String,
              frequency: ReminderFrequency.values.byName(
                row['frequency']! as String,
              ),
              hour: row['hour']! as int,
              minute: row['minute']! as int,
              weekday: Value(row['weekday'] as int?),
              dayOfMonth: Value(row['dayOfMonth'] as int?),
              scheduledAt: time(row['scheduledAt']),
              nextScheduledAt: time(row['nextScheduledAt']),
              isEnabled: Value(row['isEnabled']! as bool),
              createdAt: Value(time(row['createdAt'])),
              updatedAt: Value(time(row['updatedAt'])),
            ),
          ),
        );
        batch.insertAll(
          _db.expenseParticipants,
          records('expenseParticipants').map(
            (row) => ExpenseParticipantsCompanion.insert(
              expenseId: row['expenseId']! as String,
              userId: row['userId']! as String,
              amountOwedPaise: row['amountOwedPaise']! as int,
              ratio: Value(row['ratio'] as int?),
            ),
          ),
        );
        batch.insertAll(
          _db.expensePayments,
          records('expensePayments').map(
            (row) => ExpensePaymentsCompanion.insert(
              expenseId: row['expenseId']! as String,
              userId: row['userId']! as String,
              amountPaidPaise: row['amountPaidPaise']! as int,
            ),
          ),
        );
        batch.insertAll(
          _db.settlements,
          records('settlements').map(
            (row) => SettlementsCompanion.insert(
              id: Value(row['id']! as String),
              groupId: row['groupId']! as String,
              fromUserId: row['fromUserId']! as String,
              toUserId: row['toUserId']! as String,
              amountPaise: row['amountPaise']! as int,
              note: Value(row['note'] as String?),
              status: Value(
                SettlementStatus.values.byName(row['status']! as String),
              ),
              createdAt: Value(time(row['createdAt'])),
            ),
          ),
        );
      });
      final settingRows = optionalRecords('settings');
      final settings = settingRows.isEmpty ? null : settingRows.first;
      await (_db.update(
        _db.appSettingsTable,
      )..where((settings) => settings.id.equals(0))).write(
        AppSettingsTableCompanion(
          themeMode: Value(settings?['themeMode'] as String? ?? 'system'),
          onboardingComplete: Value(
            settings?['onboardingComplete'] as bool? ?? true,
          ),
          lockEnabled: Value(settings?['lockEnabled'] as bool? ?? false),
        ),
      );
      for (final mapping in optionalRecords('cloudIdMappings')) {
        await _db.customStatement(
          'INSERT OR REPLACE INTO cloud_id_mappings(entity_type, local_id, cloud_id) VALUES (?, ?, ?)',
          [
            mapping['entityType'] as String,
            mapping['localId'] as String,
            mapping['cloudId'] as String,
          ],
        );
      }
    });
  }
}
