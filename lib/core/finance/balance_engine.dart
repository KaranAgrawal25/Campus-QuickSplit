/// A transfer represents one user's balance against another user.
class BalanceTransfer {
  const BalanceTransfer({
    required this.fromUserId,
    required this.toUserId,
    required this.amountPaise,
  });
  final String fromUserId;
  final String toUserId;
  final int amountPaise;
}

class BalanceEngine {
  BalanceEngine._();

  /// Computes per-person net positions. Expenses contribute payments minus
  /// owed shares; completed settlements move value from debtor to creditor.
  static Map<String, int> positions({
    required Iterable<BalanceTransfer> expensePayments,
    required Iterable<BalanceTransfer> expenseShares,
    required Iterable<BalanceTransfer> settlements,
  }) {
    final result = <String, int>{};
    void add(String userId, int amount) =>
        result[userId] = (result[userId] ?? 0) + amount;
    for (final payment in expensePayments) {
      add(payment.toUserId, payment.amountPaise);
    }
    for (final share in expenseShares) {
      add(share.fromUserId, -share.amountPaise);
    }
    for (final settlement in settlements) {
      add(settlement.fromUserId, settlement.amountPaise);
      add(settlement.toUserId, -settlement.amountPaise);
    }
    return result;
  }

  static ({int owed, int owes, int net}) currentUserSummary(
    Map<String, int> positions,
    String currentUserId,
  ) {
    final net = positions[currentUserId] ?? 0;
    return (owed: net > 0 ? net : 0, owes: net < 0 ? -net : 0, net: net);
  }

  /// Produces a deterministic, reduced set of transfers that settles all
  /// supplied net positions. Positive values receive money; negative values
  /// pay money. Names never participate in this calculation.
  static List<BalanceTransfer> suggestedSettlements(
    Map<String, int> positions,
  ) {
    final creditors =
        positions.entries
            .where((entry) => entry.value > 0)
            .map((entry) => (userId: entry.key, remaining: entry.value))
            .toList()
          ..sort((a, b) {
            final amount = b.remaining.compareTo(a.remaining);
            return amount == 0 ? a.userId.compareTo(b.userId) : amount;
          });
    final debtors =
        positions.entries
            .where((entry) => entry.value < 0)
            .map((entry) => (userId: entry.key, remaining: -entry.value))
            .toList()
          ..sort((a, b) {
            final amount = b.remaining.compareTo(a.remaining);
            return amount == 0 ? a.userId.compareTo(b.userId) : amount;
          });

    final transfers = <BalanceTransfer>[];
    var creditorIndex = 0;
    var debtorIndex = 0;
    while (creditorIndex < creditors.length && debtorIndex < debtors.length) {
      final creditor = creditors[creditorIndex];
      final debtor = debtors[debtorIndex];
      final amount = creditor.remaining < debtor.remaining
          ? creditor.remaining
          : debtor.remaining;
      transfers.add(
        BalanceTransfer(
          fromUserId: debtor.userId,
          toUserId: creditor.userId,
          amountPaise: amount,
        ),
      );
      creditors[creditorIndex] = (
        userId: creditor.userId,
        remaining: creditor.remaining - amount,
      );
      debtors[debtorIndex] = (
        userId: debtor.userId,
        remaining: debtor.remaining - amount,
      );
      if (creditors[creditorIndex].remaining == 0) creditorIndex++;
      if (debtors[debtorIndex].remaining == 0) debtorIndex++;
    }
    return transfers;
  }
}
