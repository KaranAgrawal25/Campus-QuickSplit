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
}
