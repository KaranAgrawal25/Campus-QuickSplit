import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/money.dart';
import '../database/app_database.dart';

class ExportRepository {
  ExportRepository(this._db);
  final AppDatabase _db;

  /// Writes a portable spreadsheet-compatible CSV into the app's named local
  /// export folder. No email, Drive, or Android share sheet is involved.
  Future<File> exportExpensesCsv({String? groupId}) async {
    final query = _db.select(_db.expenses)
      ..where((expense) => expense.isDeleted.equals(false));
    if (groupId != null) {
      query.where((expense) => expense.groupId.equals(groupId));
    }
    final expenses = await query.get();
    final groups = await _db.select(_db.groups).get();
    final users = await _db.select(_db.users).get();
    final payments = await _db.select(_db.expensePayments).get();
    final participants = await _db.select(_db.expenseParticipants).get();
    final groupNames = {for (final group in groups) group.id: group.name};
    final userNames = {for (final user in users) user.id: user.name};

    String namesFor(Iterable<String> ids) =>
        ids.map((id) => userNames[id] ?? 'Unknown member').join('; ');
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    final rows = <String>[
      'Expense ID,Date,Time,Group,Description,Category,Amount (INR),Paid by,Participants,Split mode,Notes',
      ...expenses.map((expense) {
        final payerIds = payments
            .where((payment) => payment.expenseId == expense.id)
            .map((payment) => payment.userId);
        final participantIds = participants
            .where((participant) => participant.expenseId == expense.id)
            .map((participant) => participant.userId);
        final amount = Money(expense.totalAmountPaise).format();
        return [
          expense.id,
          DateFormat('yyyy-MM-dd').format(expense.createdAt),
          DateFormat('HH:mm').format(expense.createdAt),
          groupNames[expense.groupId] ?? 'Unknown group',
          expense.title,
          expense.category,
          amount,
          namesFor(payerIds),
          namesFor(participantIds),
          expense.splitType.name,
          expense.description ?? '',
        ].map(cell).join(',');
      }),
    ];
    final directory = await _localExportDirectory();
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File(
      p.join(directory.path, 'campus_quicksplit_expenses_$date.csv'),
    );
    return file.writeAsString('${rows.join('\n')}\n', flush: true);
  }

  Future<Directory> _localExportDirectory() async {
    // On Android this is app-owned external storage, visible as a dedicated
    // Campus QuickSplit folder in device file managers without granting broad
    // storage permissions. Desktop platforms use the app documents folder.
    final root = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(root!.path, 'Campus QuickSplit', 'Exports'),
    );
    return directory.create(recursive: true);
  }
}
