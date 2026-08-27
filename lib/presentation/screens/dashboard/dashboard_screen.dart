import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/user_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    final name = userAsync.valueOrNull?.name.split(' ').first ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          children: [
            Text(
              '${_greeting()}, $name',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppConstants.spaceLg),
            summaryAsync.when(
              data: (summary) => _BalanceCards(summary: summary),
              loading: () => const _BalanceCardsSkeleton(),
              error: (e, _) => Text('Could not load balances: $e'),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            Text('Recent activity', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppConstants.spaceSm),
            const _EmptyActivityState(),
            const SizedBox(height: AppConstants.spaceXl),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Add Expense flow lands in Phase 2'),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }
}

class _BalanceCards extends StatelessWidget {
  const _BalanceCards({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = Money(summary.netBalancePaise);
    final owed = Money(summary.youAreOwedPaise);
    final owe = Money(summary.youOwePaise);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _BalanceChip(
                label: 'You are owed',
                amount: owed,
                color: AppTheme.positiveBalance,
              ),
            ),
            const SizedBox(width: AppConstants.spaceSm),
            Expanded(
              child: _BalanceChip(
                label: 'You owe',
                amount: owe,
                color: AppTheme.negativeBalance,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spaceSm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Net balance', style: theme.textTheme.titleMedium),
                Text(
                  '${net.isNegative ? '-' : '+'}${net.abs().formatCompact()}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: net.isNegative
                        ? AppTheme.negativeBalance
                        : AppTheme.positiveBalance,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final Money amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              amount.formatCompact(),
              style: theme.textTheme.titleLarge?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCardsSkeleton extends StatelessWidget {
  const _BalanceCardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 140,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppConstants.spaceSm),
            Text(
              'Your activity will appear here',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
