import 'package:drift/drift.dart';

import '../../core/finance/split_engine.dart';
import '../database/app_database.dart';
import 'expense_repository.dart';

class RecurringExpenseRepository {
  RecurringExpenseRepository(this._db);
  final AppDatabase _db;

  Stream<List<RecurringExpenseTemplate>> watchTemplates() {
    final query = _db.select(_db.recurringExpenseTemplates)
      ..orderBy([(template) => OrderingTerm.asc(template.nextDueAt)]);
    return query.watch();
  }

  Future<void> create({
    required String sourceExpenseId,
    required int intervalDays,
    required DateTime firstDueAt,
  }) async {
    if (intervalDays <= 0) {
      throw ArgumentError('Repeat interval must be positive');
    }
    final source =
        await (_db.select(_db.expenses)..where(
              (expense) =>
                  expense.id.equals(sourceExpenseId) &
                  expense.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (source == null) throw StateError('Expense is unavailable');
    final existing =
        await (_db.select(_db.recurringExpenseTemplates)..where(
              (template) => template.sourceExpenseId.equals(sourceExpenseId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      throw StateError('This expense already has a recurring template');
    }
    await _db
        .into(_db.recurringExpenseTemplates)
        .insert(
          RecurringExpenseTemplatesCompanion.insert(
            sourceExpenseId: sourceExpenseId,
            intervalDays: intervalDays,
            nextDueAt: firstDueAt,
          ),
        );
  }

  Future<void> setActive(String templateId, bool active) =>
      (_db.update(_db.recurringExpenseTemplates)
            ..where((template) => template.id.equals(templateId)))
          .write(RecurringExpenseTemplatesCompanion(isActive: Value(active)));

  Future<void> updateInterval(String templateId, int intervalDays) async {
    if (intervalDays <= 0) {
      throw ArgumentError('Repeat interval must be positive');
    }
    await (_db.update(
      _db.recurringExpenseTemplates,
    )..where((template) => template.id.equals(templateId))).write(
      RecurringExpenseTemplatesCompanion(intervalDays: Value(intervalDays)),
    );
  }

  Future<void> stop(String templateId) => (_db.delete(
    _db.recurringExpenseTemplates,
  )..where((template) => template.id.equals(templateId))).go();

  /// Explicitly creates each due instance, then advances its schedule. No
  /// background task silently records expenses while the app is closed.
  Future<int> generateDue({DateTime? now}) async {
    final cutoff = now ?? DateTime.now();
    final templates =
        await (_db.select(_db.recurringExpenseTemplates)..where(
              (template) =>
                  template.isActive.equals(true) &
                  template.nextDueAt.isSmallerOrEqualValue(cutoff),
            ))
            .get();
    var generated = 0;
    for (final template in templates) {
      final source = await ExpenseRepository(
        _db,
      ).details(template.sourceExpenseId);
      if (source == null) {
        await setActive(template.id, false);
        continue;
      }
      final occurrenceKey =
          '${template.id}@${template.nextDueAt.toUtc().toIso8601String()}';
      final alreadyGenerated =
          await (_db.select(_db.expenses)..where(
                (expense) =>
                    expense.recurringOccurrenceKey.equals(occurrenceKey),
              ))
              .getSingleOrNull();
      if (alreadyGenerated != null) {
        await _advance(template);
        continue;
      }
      await ExpenseRepository(_db).create(
        ExpenseDraft(
          groupId: source.expense.groupId,
          title: source.expense.title,
          description: source.expense.description,
          totalAmountPaise: source.expense.totalAmountPaise,
          payerId: source.payments.first.user.id,
          payments: source.payments
              .map(
                (payment) => ExpensePaymentDraft(
                  userId: payment.user.id,
                  amountPaidPaise: payment.payment.amountPaidPaise,
                ),
              )
              .toList(),
          participants: source.shares
              .map(
                (share) => SplitShare(
                  userId: share.user.id,
                  amountPaise: share.share.amountOwedPaise,
                  ratio: share.share.ratio,
                ),
              )
              .toList(),
          splitType: source.expense.splitType,
          date: template.nextDueAt,
          category: source.expense.category,
          recurringTemplateId: template.id,
          recurringOccurrenceKey: occurrenceKey,
        ),
      );
      await _advance(template);
      generated++;
    }
    return generated;
  }

  Future<void> _advance(RecurringExpenseTemplate template) =>
      (_db.update(
        _db.recurringExpenseTemplates,
      )..where((row) => row.id.equals(template.id))).write(
        RecurringExpenseTemplatesCompanion(
          nextDueAt: Value(
            template.nextDueAt.add(Duration(days: template.intervalDays)),
          ),
        ),
      );
}
