import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/balance_repository.dart';
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
typedef DashboardSummary = BalanceSummary;

final balanceRepositoryProvider = Provider<BalanceRepository>(
  (ref) => BalanceRepository(ref.watch(appDatabaseProvider)),
);

final dashboardSummaryProvider = StreamProvider<DashboardSummary>((ref) async* {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser == null) {
    yield DashboardSummary.zero;
    return;
  }

  yield* ref.watch(balanceRepositoryProvider).watchSummary(currentUser.id);
});
