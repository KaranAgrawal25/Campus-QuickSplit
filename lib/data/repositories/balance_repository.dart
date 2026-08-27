import 'package:drift/drift.dart';

import '../../core/finance/balance_engine.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

class BalanceSummary {
  const BalanceSummary({
    required this.netBalancePaise,
    required this.youAreOwedPaise,
    required this.youOwePaise,
  });
  final int netBalancePaise, youAreOwedPaise, youOwePaise;
  static const zero = BalanceSummary(
    netBalancePaise: 0,
    youAreOwedPaise: 0,
    youOwePaise: 0,
  );
}

class BalanceRepository {
  BalanceRepository(this._db);
  final AppDatabase _db;

  Stream<BalanceSummary> watchSummary(String currentUserId) async* {
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.expenses,
            _db.expenseParticipants,
            _db.expensePayments,
            _db.settlements,
          },
        )
        .watch();
    await for (final _ in trigger) {
      yield await summary(currentUserId);
    }
  }

  Future<BalanceSummary> summary(String currentUserId) async {
    final activeExpenses = await (_db.select(
      _db.expenses,
    )..where((e) => e.isDeleted.equals(false))).get();
    final ids = activeExpenses.map((expense) => expense.id).toSet();
    final payments = await _db.select(_db.expensePayments).get();
    final shares = await _db.select(_db.expenseParticipants).get();
    final settlements = await (_db.select(
      _db.settlements,
    )..where((s) => s.status.equals(SettlementStatus.completed.name))).get();
    final positions = BalanceEngine.positions(
      expensePayments: payments
          .where((payment) => ids.contains(payment.expenseId))
          .map(
            (payment) => BalanceTransfer(
              fromUserId: '',
              toUserId: payment.userId,
              amountPaise: payment.amountPaidPaise,
            ),
          ),
      expenseShares: shares
          .where((share) => ids.contains(share.expenseId))
          .map(
            (share) => BalanceTransfer(
              fromUserId: share.userId,
              toUserId: '',
              amountPaise: share.amountOwedPaise,
            ),
          ),
      settlements: settlements.map(
        (settlement) => BalanceTransfer(
          fromUserId: settlement.fromUserId,
          toUserId: settlement.toUserId,
          amountPaise: settlement.amountPaise,
        ),
      ),
    );
    final result = BalanceEngine.currentUserSummary(positions, currentUserId);
    return BalanceSummary(
      netBalancePaise: result.net,
      youAreOwedPaise: result.owed,
      youOwePaise: result.owes,
    );
  }

  Future<void> recordSettlement({
    required String groupId,
    required String fromUserId,
    required String toUserId,
    required int amountPaise,
    required DateTime date,
    String? note,
  }) async {
    if (amountPaise <= 0 || fromUserId == toUserId) {
      throw ArgumentError('Settlement needs two people and a positive amount');
    }
    await _db
        .into(_db.settlements)
        .insert(
          SettlementsCompanion.insert(
            groupId: groupId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            amountPaise: amountPaise,
            createdAt: Value(date),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            status: const Value(SettlementStatus.completed),
          ),
        );
  }

  Stream<List<Settlement>> watchRecentSettlements() {
    final query = _db.select(_db.settlements)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    return query.watch();
  }
}
