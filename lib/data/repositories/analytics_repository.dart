import '../database/app_database.dart';
import 'balance_repository.dart';

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalSpentPaise,
    required this.averageExpensePaise,
    required this.largestExpense,
    required this.categoryTotals,
    required this.groupTotals,
    required this.personalContributionPaise,
    required this.personalSharePaise,
    required this.youOwePaise,
    required this.youAreOwedPaise,
    required this.monthTotals,
  });

  final int totalSpentPaise;
  final int averageExpensePaise;
  final Expense? largestExpense;
  final Map<String, int> categoryTotals;
  final Map<String, int> groupTotals;
  final int personalContributionPaise;
  final int personalSharePaise;
  final int youOwePaise;
  final int youAreOwedPaise;
  final Map<DateTime, int> monthTotals;

  bool get isEmpty => personalContributionPaise == 0 && personalSharePaise == 0;

  String? get mostUsedCategory {
    if (categoryTotals.isEmpty) return null;
    return categoryTotals.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }
}

/// Read-only reporting built from the same normalized expense/payment rows as
/// balances. It intentionally ignores archived groups and soft-deleted
/// expenses, so an analytics card can never disagree with the active UI.
class AnalyticsRepository {
  AnalyticsRepository(this._db);
  final AppDatabase _db;

  Stream<AnalyticsSummary> watchSummary(String currentUserId) async* {
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.groups, _db.expenses, _db.expensePayments},
        )
        .watch();
    await for (final _ in trigger) {
      yield await summary(currentUserId);
    }
  }

  Future<AnalyticsSummary> summary(String currentUserId) async {
    final groups = await _db.select(_db.groups).get();
    final activeGroupNames = {
      for (final group in groups.where((group) => !group.isArchived))
        group.id: group.name,
    };
    final expenses = (await _db.select(_db.expenses).get())
        .where(
          (expense) =>
              !expense.isDeleted &&
              activeGroupNames.containsKey(expense.groupId),
        )
        .toList();
    final expenseIds = expenses.map((expense) => expense.id).toSet();
    final payments = await _db.select(_db.expensePayments).get();

    final categoryTotals = <String, int>{};
    final groupTotals = <String, int>{};
    final monthTotals = <DateTime, int>{};
    var total = 0;
    for (final expense in expenses) {
      total += expense.totalAmountPaise;
    }
    final personalContribution = payments
        .where(
          (payment) =>
              expenseIds.contains(payment.expenseId) &&
              payment.userId == currentUserId,
        )
        .fold<int>(0, (sum, payment) => sum + payment.amountPaidPaise);
    final shares = await _db.select(_db.expenseParticipants).get();
    final personalShare = shares
        .where(
          (share) =>
              expenseIds.contains(share.expenseId) &&
              share.userId == currentUserId,
        )
        .fold<int>(0, (sum, share) => sum + share.amountOwedPaise);

    final expensesById = {for (final expense in expenses) expense.id: expense};
    for (final payment in payments.where(
      (item) => expenseIds.contains(item.expenseId) && item.userId == currentUserId,
    )) {
      final expense = expensesById[payment.expenseId]!;
      categoryTotals.update(
        expense.category,
        (value) => value + payment.amountPaidPaise,
        ifAbsent: () => payment.amountPaidPaise,
      );
      final groupName = activeGroupNames[expense.groupId]!;
      groupTotals.update(
        groupName,
        (value) => value + payment.amountPaidPaise,
        ifAbsent: () => payment.amountPaidPaise,
      );
      final month = DateTime(expense.createdAt.year, expense.createdAt.month);
      monthTotals.update(
        month,
        (value) => value + payment.amountPaidPaise,
        ifAbsent: () => payment.amountPaidPaise,
      );
    }
    final balance = await BalanceRepository(_db).summary(currentUserId);

    Expense? largest;
    for (final expense in expenses) {
      if (largest == null ||
          expense.totalAmountPaise > largest.totalAmountPaise) {
        largest = expense;
      }
    }
    return AnalyticsSummary(
      totalSpentPaise: total,
      averageExpensePaise: expenses.isEmpty ? 0 : total ~/ expenses.length,
      largestExpense: largest,
      categoryTotals: categoryTotals,
      groupTotals: groupTotals,
      personalContributionPaise: personalContribution,
      personalSharePaise: personalShare,
      youOwePaise: balance.youOwePaise,
      youAreOwedPaise: balance.youAreOwedPaise,
      monthTotals: monthTotals,
    );
  }
}
