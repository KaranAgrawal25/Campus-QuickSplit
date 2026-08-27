import 'package:drift/drift.dart';

import '../../core/finance/split_engine.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

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
  });
  final String groupId, title, payerId, category;
  final int totalAmountPaise;
  final List<SplitShare> participants;
  final SplitTypeDb splitType;
  final DateTime date;
  final String? description;
}

class ExpenseDetailsData {
  const ExpenseDetailsData({
    required this.expense,
    required this.group,
    required this.payer,
    required this.shares,
  });
  final Expense expense;
  final Group group;
  final User payer;
  final List<({User user, ExpenseParticipant share})> shares;
}

class ExpenseRepository {
  ExpenseRepository(this._db);
  final AppDatabase _db;

  Future<String> create(ExpenseDraft draft) async {
    if (draft.totalAmountPaise <= 0 ||
        draft.title.trim().isEmpty ||
        draft.participants.isEmpty) {
      throw ArgumentError('Enter a title, positive amount, and participants');
    }
    if (draft.participants.fold<int>(
          0,
          (sum, share) => sum + share.amountPaise,
        ) !=
        draft.totalAmountPaise) {
      throw ArgumentError('Participant shares must equal the total');
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
    if (!memberIds.contains(draft.payerId) ||
        draft.participants.any((share) => !memberIds.contains(share.userId))) {
      throw StateError('Payer and participants must belong to the group');
    }
    return _db.transaction(() async {
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
              description: Value(
                draft.description?.trim().isEmpty ?? true
                    ? null
                    : draft.description!.trim(),
              ),
            ),
          );
      await _db.batch((batch) {
        batch.insertAll(
          _db.expenseParticipants,
          draft.participants.map(
            (share) => ExpenseParticipantsCompanion.insert(
              expenseId: expense.id,
              userId: share.userId,
              amountOwedPaise: share.amountPaise,
              ratio: Value(share.ratio),
            ),
          ),
        );
        batch.insert(
          _db.expensePayments,
          ExpensePaymentsCompanion.insert(
            expenseId: expense.id,
            userId: draft.payerId,
            amountPaidPaise: draft.totalAmountPaise,
          ),
        );
      });
      return expense.id;
    });
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
    final payment = await (_db.select(
      _db.expensePayments,
    )..where((p) => p.expenseId.equals(expenseId))).getSingle();
    final payer = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(payment.userId))).getSingle();
    final participantRows = await (_db.select(
      _db.expenseParticipants,
    )..where((p) => p.expenseId.equals(expenseId))).get();
    final shares = <({User user, ExpenseParticipant share})>[];
    for (final participant in participantRows) {
      final user = await (_db.select(
        _db.users,
      )..where((u) => u.id.equals(participant.userId))).getSingle();
      shares.add((user: user, share: participant));
    }
    return ExpenseDetailsData(
      expense: expense,
      group: group,
      payer: payer,
      shares: shares,
    );
  }

  Future<void> delete(String expenseId) =>
      (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId))).write(
        const ExpensesCompanion(isDeleted: Value(true)),
      );
}
