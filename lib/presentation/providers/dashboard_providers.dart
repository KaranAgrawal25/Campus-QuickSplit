import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/balance_repository.dart';
import '../../data/repositories/analytics_repository.dart';
import 'database_provider.dart';
import 'user_providers.dart';

/// Live dashboard balances for the current user. The repository aggregates
/// group-scoped settlement transfers so the gross receivable, gross payable,
/// and their net remain distinct.
typedef DashboardSummary = BalanceSummary;

final balanceRepositoryProvider = Provider<BalanceRepository>(
  (ref) => BalanceRepository(ref.watch(appDatabaseProvider)),
);

final dashboardSummaryProvider = StreamProvider<DashboardSummary>((ref) async* {
  // Capture every provider dependency before the first await. A StreamProvider
  // can be invalidated while waiting for its current-user stream; consulting
  // ref again from a later stream callback then violates Riverpod's lifecycle.
  final currentUserFuture = ref.watch(currentUserProvider.future);
  final balanceRepository = ref.watch(balanceRepositoryProvider);
  final currentUser = await currentUserFuture;

  if (currentUser == null) {
    yield DashboardSummary.zero;
    return;
  }

  yield* balanceRepository.watchSummary(currentUser.id);
});

/// Live, group-scoped smart settlement suggestions. The underlying balance
/// engine still performs all calculation; this provider only refreshes UI.
final groupSettlementSuggestionsProvider =
    StreamProvider.family<List<GroupSettlementSuggestion>, String>((
      ref,
      groupId,
    ) async* {
      final db = ref.watch(appDatabaseProvider);
      final balanceRepository = ref.watch(balanceRepositoryProvider);
      final trigger = db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              db.expenses,
              db.expenseParticipants,
              db.expensePayments,
              db.settlements,
            },
          )
          .watch();
      await for (final _ in trigger) {
        yield await balanceRepository.suggestionsForGroup(groupId);
      }
    });

final analyticsSummaryProvider = StreamProvider<AnalyticsSummary>((ref) async* {
  final userFuture = ref.watch(currentUserProvider.future);
  final analyticsRepository = ref.watch(analyticsRepositoryProvider);
  final user = await userFuture;
  if (user == null) {
    yield const AnalyticsSummary(
      totalSpentPaise: 0,
      averageExpensePaise: 0,
      largestExpense: null,
      categoryTotals: {},
      groupTotals: {},
      personalContributionPaise: 0,
      personalSharePaise: 0,
      youOwePaise: 0,
      youAreOwedPaise: 0,
      monthTotals: {},
    );
    return;
  }
  yield* analyticsRepository.watchSummary(user.id);
});

final groupFinancialSummaryProvider =
    StreamProvider.family<GroupFinancialSummary, String>((ref, groupId) async* {
      final userFuture = ref.watch(currentUserProvider.future);
      final balanceRepository = ref.watch(balanceRepositoryProvider);
      final db = ref.watch(appDatabaseProvider);
      final user = await userFuture;
      if (user == null) return;
      final trigger = db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              db.expenses,
              db.expenseParticipants,
              db.expensePayments,
              db.settlements,
            },
          )
          .watch();
      await for (final _ in trigger) {
        yield await balanceRepository.groupSummary(
          groupId: groupId,
          currentUserId: user.id,
        );
      }
    });
