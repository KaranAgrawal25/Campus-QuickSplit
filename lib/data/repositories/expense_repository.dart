import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/finance/split_engine.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'sync_repository.dart';

class ExpenseDraft {
  const ExpenseDraft({
    required this.groupId,
    required this.title,
    required this.totalAmountPaise,
    required this.payerId,
    required this.participants,
    required this.splitType,
    required this.date,
    this.description,
    this.category = 'Other',
    this.payments = const [],
    this.receiptPath,
    this.recurringTemplateId,
    this.recurringOccurrenceKey,
  });
  final String groupId, title, payerId, category;
  final int totalAmountPaise;
  final List<SplitShare> participants;
  final SplitTypeDb splitType;
  final DateTime date;
  final String? description;
  final List<ExpensePaymentDraft> payments;

  /// A local source path selected by the user, or the existing stored path
  /// while editing. The repository copies new images into app-owned storage.
  final String? receiptPath;
  final String? recurringTemplateId;
  final String? recurringOccurrenceKey;
}

/// An upfront contribution to an expense. The legacy [ExpenseDraft.payerId]
/// remains the single-payer default so existing screens and records stay
/// compatible while callers can opt into split payments.
class ExpensePaymentDraft {
  const ExpensePaymentDraft({
    required this.userId,
    required this.amountPaidPaise,
  });

  final String userId;
  final int amountPaidPaise;
}

class ExpenseDetailsData {
  const ExpenseDetailsData({
    required this.expense,
    required this.group,
    required this.payments,
    required this.shares,
  });
  final Expense expense;
  final Group group;
  final List<({User user, ExpensePayment payment})> payments;
  final List<({User user, ExpenseParticipant share})> shares;
}

class ExpenseRepository {
  ExpenseRepository(this._db);
  final AppDatabase _db;

  Future<String> create(ExpenseDraft draft) async {
    final payments = await _validateDraft(draft);
    final expense = await _db.transaction(() async {
      final expense = await _db
          .into(_db.expenses)
          .insertReturning(
            ExpensesCompanion.insert(
              groupId: draft.groupId,
              title: draft.title.trim(),
              totalAmountPaise: draft.totalAmountPaise,
              category: draft.category,
              splitType: Value(draft.splitType),
              createdAt: Value(draft.date),
              description: Value(_normalizedDescription(draft.description)),
              recurringTemplateId: Value(draft.recurringTemplateId),
              recurringOccurrenceKey: Value(draft.recurringOccurrenceKey),
            ),
          );
      await _replaceChildren(expense.id, draft, payments);
      return expense;
    });
    if (draft.receiptPath != null) {
      await _replaceReceipt(expense.id, draft.receiptPath);
    }
    await _enqueueExpense(expense, draft, payments);
    return expense.id;
  }

  /// Atomically replaces an active expense and all of its financial rows.
  /// Existing settlements are deliberately not altered; the normal balance
  /// engine recalculates from the updated expense and settlement history.
  Future<void> update(String expenseId, ExpenseDraft draft) async {
    final payments = await _validateDraft(draft);
    final existing =
        await (_db.select(_db.expenses)..where(
              (expense) =>
                  expense.id.equals(expenseId) &
                  expense.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (existing == null) throw StateError('Expense no longer exists');
    if (existing.groupId != draft.groupId) {
      throw ArgumentError('An expense cannot be moved between groups');
    }
    final updated = await _db.transaction(() async {
      await (_db.update(
        _db.expenses,
      )..where((e) => e.id.equals(expenseId))).write(
        ExpensesCompanion(
          title: Value(draft.title.trim()),
          description: Value(_normalizedDescription(draft.description)),
          totalAmountPaise: Value(draft.totalAmountPaise),
          category: Value(draft.category),
          splitType: Value(draft.splitType),
          createdAt: Value(draft.date),
        ),
      );
      await _replaceChildren(expenseId, draft, payments);
      return (_db.select(
        _db.expenses,
      )..where((e) => e.id.equals(expenseId))).getSingle();
    });
    if (draft.receiptPath != existing.receiptPath) {
      await _replaceReceipt(
        expenseId,
        draft.receiptPath,
        oldPath: existing.receiptPath,
      );
    }
    await _enqueueExpense(updated, draft, payments);
  }

  Future<List<ExpensePaymentDraft>> _validateDraft(ExpenseDraft draft) async {
    if (draft.totalAmountPaise <= 0 ||
        draft.title.trim().isEmpty ||
        draft.participants.isEmpty) {
      throw ArgumentError('Enter a title, positive amount, and participants');
    }
    final payments = draft.payments.isEmpty
        ? [
            ExpensePaymentDraft(
              userId: draft.payerId,
              amountPaidPaise: draft.totalAmountPaise,
            ),
          ]
        : draft.payments;
    if (draft.participants.fold<int>(
          0,
          (sum, share) => sum + share.amountPaise,
        ) !=
        draft.totalAmountPaise) {
      throw ArgumentError('Participant shares must equal the total');
    }
    if (payments.isEmpty ||
        payments.any((payment) => payment.amountPaidPaise <= 0) ||
        payments.fold<int>(
              0,
              (sum, payment) => sum + payment.amountPaidPaise,
            ) !=
            draft.totalAmountPaise) {
      throw ArgumentError('Payer amounts must equal the total');
    }
    if (payments.map((payment) => payment.userId).toSet().length !=
        payments.length) {
      throw ArgumentError('A payer can only appear once');
    }
    if (draft.participants.map((share) => share.userId).toSet().length !=
        draft.participants.length) {
      throw ArgumentError('A participant can only appear once');
    }
    final group =
        await (_db.select(_db.groups)..where(
              (g) => g.id.equals(draft.groupId) & g.isArchived.equals(false),
            ))
            .getSingleOrNull();
    if (group == null) throw StateError('Group no longer exists');
    final members = await (_db.select(
      _db.groupMembers,
    )..where((m) => m.groupId.equals(draft.groupId))).get();
    final memberIds = members.map((member) => member.userId).toSet();
    if (payments.any((payment) => !memberIds.contains(payment.userId)) ||
        draft.participants.any((share) => !memberIds.contains(share.userId))) {
      throw StateError('Payer and participants must belong to the group');
    }
    return payments;
  }

  String? _normalizedDescription(String? description) =>
      description?.trim().isEmpty ?? true ? null : description!.trim();

  Future<void> _replaceChildren(
    String expenseId,
    ExpenseDraft draft,
    List<ExpensePaymentDraft> payments,
  ) async {
    await (_db.delete(
      _db.expenseParticipants,
    )..where((participant) => participant.expenseId.equals(expenseId))).go();
    await (_db.delete(
      _db.expensePayments,
    )..where((payment) => payment.expenseId.equals(expenseId))).go();
    await _db.batch((batch) {
      batch.insertAll(
        _db.expenseParticipants,
        draft.participants.map(
          (share) => ExpenseParticipantsCompanion.insert(
            expenseId: expenseId,
            userId: share.userId,
            amountOwedPaise: share.amountPaise,
            ratio: Value(share.ratio),
          ),
        ),
      );
      batch.insertAll(
        _db.expensePayments,
        payments.map(
          (payment) => ExpensePaymentsCompanion.insert(
            expenseId: expenseId,
            userId: payment.userId,
            amountPaidPaise: payment.amountPaidPaise,
          ),
        ),
      );
    });
  }

  Future<void> _enqueueExpense(
    Expense expense,
    ExpenseDraft draft,
    List<ExpensePaymentDraft> payments,
  ) async {
    await SyncRepository(_db).enqueueUpsert(
      entityType: 'expense',
      entityId: expense.id,
      payload: {
        'id': expense.id,
        'groupId': draft.groupId,
        'title': expense.title,
        'description': expense.description,
        'totalAmountPaise': expense.totalAmountPaise,
        'category': expense.category,
        'splitType': expense.splitType.name,
        'createdAt': expense.createdAt.toUtc().toIso8601String(),
        'isDeleted': expense.isDeleted,
        'payments': payments
            .map(
              (payment) => {
                'userId': payment.userId,
                'amountPaidPaise': payment.amountPaidPaise,
              },
            )
            .toList(),
        'participants': draft.participants
            .map(
              (share) => {
                'userId': share.userId,
                'amountOwedPaise': share.amountPaise,
                'ratio': share.ratio,
              },
            )
            .toList(),
      },
    );
  }

  Future<void> _replaceReceipt(
    String expenseId,
    String? sourcePath, {
    String? oldPath,
  }) async {
    String? storedPath;
    if (sourcePath != null) {
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw StateError('The selected receipt is no longer available');
      }
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(documents.path, 'receipts'));
      await directory.create(recursive: true);
      final extension = p.extension(source.path).isEmpty
          ? '.jpg'
          : p.extension(source.path).toLowerCase();
      storedPath = p.join(directory.path, '$expenseId$extension');
      if (p.normalize(source.path) != p.normalize(storedPath)) {
        await source.copy(storedPath);
      }
    }
    await (_db.update(_db.expenses)
          ..where((expense) => expense.id.equals(expenseId)))
        .write(ExpensesCompanion(receiptPath: Value(storedPath)));
    if (oldPath != null && oldPath != storedPath) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) await oldFile.delete();
    }
  }

  Stream<List<Expense>> watchRecent({String? groupId}) {
    final query = _db.select(_db.expenses)
      ..where((e) => e.isDeleted.equals(false));
    if (groupId != null) query.where((e) => e.groupId.equals(groupId));
    query.orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    return query.watch();
  }

  Future<ExpenseDetailsData?> details(String expenseId) async {
    final expense =
        await (_db.select(
              _db.expenses,
            )..where((e) => e.id.equals(expenseId) & e.isDeleted.equals(false)))
            .getSingleOrNull();
    if (expense == null) return null;
    final group = await (_db.select(
      _db.groups,
    )..where((g) => g.id.equals(expense.groupId))).getSingle();
    final paymentRows = await (_db.select(
      _db.expensePayments,
    )..where((p) => p.expenseId.equals(expenseId))).get();
    final payments = <({User user, ExpensePayment payment})>[];
    for (final payment in paymentRows) {
      final user = await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(payment.userId))).getSingle();
      payments.add((user: user, payment: payment));
    }
    final participantRows = await (_db.select(
      _db.expenseParticipants,
    )..where((p) => p.expenseId.equals(expenseId))).get();
    final shares = <({User user, ExpenseParticipant share})>[];
    final uniqueParticipants = <String, ExpenseParticipant>{
      for (final participant in participantRows)
        participant.userId: participant,
    };
    for (final participant in uniqueParticipants.values) {
      final user = await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(participant.userId))).getSingle();
      shares.add((user: user, share: participant));
    }
    return ExpenseDetailsData(
      expense: expense,
      group: group,
      payments: payments,
      shares: shares,
    );
  }

  /// Hides an expense without discarding its financial history. Keeping the
  /// row makes an Undo operation exact and allows a future sync transport to
  /// propagate the deletion as an ordinary upsert rather than losing state.
  Future<void> delete(String expenseId) async {
    final expense = await (_db.select(
      _db.expenses,
    )..where((e) => e.id.equals(expenseId))).getSingleOrNull();
    if (expense == null || expense.isDeleted) {
      throw StateError('Expense no longer exists');
    }
    await (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId)))
        .write(const ExpensesCompanion(isDeleted: Value(true)));
    await _enqueueDeletion(expense, isDeleted: true);
  }

  /// Restores a soft-deleted expense with its original payer and share rows.
  Future<void> restore(String expenseId) async {
    final expense = await (_db.select(
      _db.expenses,
    )..where((e) => e.id.equals(expenseId))).getSingleOrNull();
    if (expense == null || !expense.isDeleted) {
      throw StateError('Expense cannot be restored');
    }
    await (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId)))
        .write(const ExpensesCompanion(isDeleted: Value(false)));
    await _enqueueDeletion(expense, isDeleted: false);
  }

  Future<void> _enqueueDeletion(Expense expense, {required bool isDeleted}) =>
      SyncRepository(_db).enqueueUpsert(
        entityType: 'expense',
        entityId: expense.id,
        payload: {
          'id': expense.id,
          'groupId': expense.groupId,
          'isDeleted': isDeleted,
        },
      );
}
