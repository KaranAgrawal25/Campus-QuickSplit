import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';
import 'user_providers.dart';

/// Aggregate net balance for the current user, computed directly from
/// stored expenses.
///
/// This is intentionally a simple aggregate
/// (totalPaid - totalOwed across everything) for the Phase 1 dashboard
/// shell.
///
/// The full per-counterparty breakdown ("who specifically owes whom")
/// is the job of the dedicated BalanceEngine landing in Phase 3.
///
/// The important property already true here: every number is a live
/// query result, never a literal.
class DashboardSummary {
  const DashboardSummary({
    required this.netBalancePaise,
    required this.youAreOwedPaise,
    required this.youOwePaise,
  });

  final int netBalancePaise;
  final int youAreOwedPaise;
  final int youOwePaise;

  static const zero = DashboardSummary(
    netBalancePaise: 0,
    youAreOwedPaise: 0,
    youOwePaise: 0,
  );
}

final dashboardSummaryProvider =
StreamProvider<DashboardSummary>((ref) async* {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser == null) {
    yield DashboardSummary.zero;
    return;
  }

  final db = ref.watch(appDatabaseProvider);

  // A single query computing both sums via correlated subqueries.
  //
  // `readsFrom` tells Drift which tables to watch for invalidation,
  // since customSelect can't infer that from a raw query string.
  final query = db.customSelect(
    '''
    SELECT
      COALESCE((
        SELECT SUM(ep.amount_owed_paise)
        FROM expense_participants ep
        INNER JOIN expenses e ON e.id = ep.expense_id
        WHERE ep.user_id = ?1 AND e.is_deleted = 0
      ), 0) AS total_owed,
      COALESCE((
        SELECT SUM(epay.amount_paid_paise)
        FROM expense_payments epay
        INNER JOIN expenses e2 ON e2.id = epay.expense_id
        WHERE epay.user_id = ?1 AND e2.is_deleted = 0
      ), 0) AS total_paid
    ''',
    variables: [
      Variable.withString(currentUser.id),
    ],
    readsFrom: {
      db.expenseParticipants,
      db.expensePayments,
      db.expenses,
    },
  );

  yield* query.watchSingle().map((row) {
    final totalOwed = row.read<int>('total_owed');
    final totalPaid = row.read<int>('total_paid');

    final net = totalPaid - totalOwed;

    return DashboardSummary(
      netBalancePaise: net,
      youAreOwedPaise: net > 0 ? net : 0,
      youOwePaise: net < 0 ? -net : 0,
    );
  });
});