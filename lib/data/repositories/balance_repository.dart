import 'package:drift/drift.dart';

import '../../core/finance/balance_engine.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'sync_repository.dart';

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

/// A transfer returned by the existing smart-settlement engine, scoped to one
/// group. User IDs—not display names—remain the identity used throughout.
class GroupSettlementSuggestion {
  const GroupSettlementSuggestion({
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amountPaise,
  });

  final String groupId;
  final String fromUserId;
  final String toUserId;
  final int amountPaise;
}

class GroupFinancialSummary {
  const GroupFinancialSummary({
    required this.totalSpentPaise,
    required this.yourContributionPaise,
    required this.yourSharePaise,
    required this.netBalancePaise,
  });

  final int totalSpentPaise;
  final int yourContributionPaise;
  final int yourSharePaise;
  final int netBalancePaise;
}

class BalanceRepository {
  BalanceRepository(this._db);
  final AppDatabase _db;

  Stream<BalanceSummary> watchSummary(String currentUserId) async* {
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.groups,
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
    final activeGroupIds =
        (await (_db.select(
              _db.groups,
            )..where((group) => group.isArchived.equals(false))).get())
            .map((group) => group.id)
            .toSet();
    final activeExpenses = await (_db.select(
      _db.expenses,
    )..where((e) => e.isDeleted.equals(false))).get();
    final visibleExpenses = activeExpenses
        .where((expense) => activeGroupIds.contains(expense.groupId))
        .toList();
    final payments = await _db.select(_db.expensePayments).get();
    final shares = await _db.select(_db.expenseParticipants).get();
    final settlements =
        await (_db.select(_db.settlements)
              ..where((s) => s.status.equals(SettlementStatus.completed.name)))
            .get()
            .then(
              (rows) => rows
                  .where(
                    (settlement) => activeGroupIds.contains(settlement.groupId),
                  )
                  .toList(),
            );
    // A single position across every group only gives a net value. The
    // dashboard needs gross receivables and payables as well, so preserve the
    // existing group-scoped settlement calculation used by Group Detail and
    // aggregate its transfers. This deliberately does not offset a debt in
    // one group against a receivable in another.
    final expensesByGroup = <String, Set<String>>{};
    for (final expense in visibleExpenses) {
      expensesByGroup.putIfAbsent(expense.groupId, () => {}).add(expense.id);
    }
    final groupIds = {
      ...expensesByGroup.keys,
      ...settlements.map((settlement) => settlement.groupId),
    };

    var youAreOwedPaise = 0;
    var youOwePaise = 0;
    for (final groupId in groupIds) {
      final expenseIds = expensesByGroup[groupId] ?? const <String>{};
      final positions = BalanceEngine.positions(
        expensePayments: payments
            .where((payment) => expenseIds.contains(payment.expenseId))
            .map(
              (payment) => BalanceTransfer(
                fromUserId: '',
                toUserId: payment.userId,
                amountPaise: payment.amountPaidPaise,
              ),
            ),
        expenseShares: shares
            .where((share) => expenseIds.contains(share.expenseId))
            .map(
              (share) => BalanceTransfer(
                fromUserId: share.userId,
                toUserId: '',
                amountPaise: share.amountOwedPaise,
              ),
            ),
        settlements: settlements
            .where((settlement) => settlement.groupId == groupId)
            .map(
              (settlement) => BalanceTransfer(
                fromUserId: settlement.fromUserId,
                toUserId: settlement.toUserId,
                amountPaise: settlement.amountPaise,
              ),
            ),
      );
      for (final transfer in BalanceEngine.suggestedSettlements(positions)) {
        if (transfer.toUserId == currentUserId) {
          youAreOwedPaise += transfer.amountPaise;
        }
        if (transfer.fromUserId == currentUserId) {
          youOwePaise += transfer.amountPaise;
        }
      }
    }
    return BalanceSummary(
      netBalancePaise: youAreOwedPaise - youOwePaise,
      youAreOwedPaise: youAreOwedPaise,
      youOwePaise: youOwePaise,
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
    final settlement = await _db
        .into(_db.settlements)
        .insertReturning(
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
    await _queueSettlement(settlement);
  }

  /// A group-scoped view of the current user's actual payments and fair
  /// shares. This is derived from persisted rows, never from form state.
  Future<GroupFinancialSummary> groupSummary({
    required String groupId,
    required String currentUserId,
  }) async {
    final expenses =
        await (_db.select(_db.expenses)..where(
              (expense) =>
                  expense.groupId.equals(groupId) &
                  expense.isDeleted.equals(false),
            ))
            .get();
    final ids = expenses.map((expense) => expense.id).toSet();
    final payments = await (_db.select(
      _db.expensePayments,
    )..where((payment) => payment.userId.equals(currentUserId))).get();
    final shares = await (_db.select(
      _db.expenseParticipants,
    )..where((share) => share.userId.equals(currentUserId))).get();
    final settlements =
        await (_db.select(_db.settlements)..where(
              (settlement) =>
                  settlement.groupId.equals(groupId) &
                  settlement.status.equals(SettlementStatus.completed.name),
            ))
            .get();
    final contributed = payments
        .where((payment) => ids.contains(payment.expenseId))
        .fold<int>(0, (sum, payment) => sum + payment.amountPaidPaise);
    final owed = shares
        .where((share) => ids.contains(share.expenseId))
        .fold<int>(0, (sum, share) => sum + share.amountOwedPaise);
    var net = contributed - owed;
    for (final settlement in settlements) {
      if (settlement.fromUserId == currentUserId) net += settlement.amountPaise;
      if (settlement.toUserId == currentUserId) net -= settlement.amountPaise;
    }
    return GroupFinancialSummary(
      totalSpentPaise: expenses.fold<int>(
        0,
        (sum, expense) => sum + expense.totalAmountPaise,
      ),
      yourContributionPaise: contributed,
      yourSharePaise: owed,
      netBalancePaise: net,
    );
  }

  /// Returns the same deterministic settlement suggestions as [BalanceEngine],
  /// but only for the financial history in [groupId].
  Future<List<GroupSettlementSuggestion>> suggestionsForGroup(
    String groupId,
  ) async {
    final transfers = await _suggestedTransfersForGroup(groupId);
    return transfers
        .map(
          (transfer) => GroupSettlementSuggestion(
            groupId: groupId,
            fromUserId: transfer.fromUserId,
            toUserId: transfer.toUserId,
            amountPaise: transfer.amountPaise,
          ),
        )
        .toList();
  }

  /// Records only a currently valid full smart-settlement suggestion. This
  /// guards against duplicate confirmation and stale payment screens without
  /// creating a second settlement mechanism or enabling partial repayments.
  Future<void> recordSuggestedSettlement({
    required String groupId,
    required String fromUserId,
    required String toUserId,
    required int amountPaise,
    String? note,
  }) async {
    if (amountPaise <= 0 || fromUserId == toUserId) {
      throw ArgumentError('Settlement needs two people and a positive amount');
    }
    await _db.transaction(() async {
      final suggestions = await _suggestedTransfersForGroup(groupId);
      final isStillOutstanding = suggestions.any(
        (transfer) =>
            transfer.fromUserId == fromUserId &&
            transfer.toUserId == toUserId &&
            transfer.amountPaise == amountPaise,
      );
      if (!isStillOutstanding) {
        throw StateError('This settlement is already completed or has changed');
      }
      final settlement = await _db
          .into(_db.settlements)
          .insertReturning(
            SettlementsCompanion.insert(
              groupId: groupId,
              fromUserId: fromUserId,
              toUserId: toUserId,
              amountPaise: amountPaise,
              createdAt: Value(DateTime.now()),
              note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
              status: const Value(SettlementStatus.completed),
            ),
          );
      await _queueSettlement(settlement);
    });
  }

  Future<void> _queueSettlement(Settlement settlement) =>
      SyncRepository(_db).enqueueUpsert(
        entityType: 'settlement',
        entityId: settlement.id,
        payload: {
          'id': settlement.id,
          'groupId': settlement.groupId,
          'fromUserId': settlement.fromUserId,
          'toUserId': settlement.toUserId,
          'amountPaise': settlement.amountPaise,
          'note': settlement.note,
          'status': settlement.status.name,
          'createdAt': settlement.createdAt.toUtc().toIso8601String(),
        },
      );

  Future<List<BalanceTransfer>> _suggestedTransfersForGroup(
    String groupId,
  ) async {
    final group = await (_db.select(
      _db.groups,
    )..where((group) => group.id.equals(groupId))).getSingleOrNull();
    if (group == null) throw StateError('Group no longer exists');

    final expenses =
        await (_db.select(_db.expenses)..where(
              (expense) =>
                  expense.groupId.equals(groupId) &
                  expense.isDeleted.equals(false),
            ))
            .get();
    final expenseIds = expenses.map((expense) => expense.id).toSet();
    final payments = await _db.select(_db.expensePayments).get();
    final shares = await _db.select(_db.expenseParticipants).get();
    final settlements =
        await (_db.select(_db.settlements)..where(
              (settlement) =>
                  settlement.groupId.equals(groupId) &
                  settlement.status.equals(SettlementStatus.completed.name),
            ))
            .get();
    final positions = BalanceEngine.positions(
      expensePayments: payments
          .where((payment) => expenseIds.contains(payment.expenseId))
          .map(
            (payment) => BalanceTransfer(
              fromUserId: '',
              toUserId: payment.userId,
              amountPaise: payment.amountPaidPaise,
            ),
          ),
      expenseShares: shares
          .where((share) => expenseIds.contains(share.expenseId))
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
    return BalanceEngine.suggestedSettlements(positions);
  }

  Stream<List<Settlement>> watchRecentSettlements() {
    final query = _db.select(_db.settlements)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    return query.watch();
  }
}
