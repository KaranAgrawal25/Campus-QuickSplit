import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../providers/dashboard_providers.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(analyticsSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Could not load analytics. Please try again.'),
        ),
        data: (data) {
          if (data.isEmpty) return const _EmptyAnalytics();
          return ListView(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: AppConstants.spaceSm,
                  runSpacing: AppConstants.spaceSm,
                  children: [
                    _MetricCard(
                      'Your spending',
                      Money(data.personalContributionPaise).formatCompact(),
                      width: (constraints.maxWidth - AppConstants.spaceSm) / 2,
                    ),
                    _MetricCard(
                      'Your share',
                      Money(data.personalSharePaise).formatCompact(),
                      width: (constraints.maxWidth - AppConstants.spaceSm) / 2,
                    ),
                    _MetricCard(
                      'You owe',
                      Money(data.youOwePaise).formatCompact(),
                      width: (constraints.maxWidth - AppConstants.spaceSm) / 2,
                    ),
                    _MetricCard(
                      'You’re owed',
                      Money(data.youAreOwedPaise).formatCompact(),
                      width: (constraints.maxWidth - AppConstants.spaceSm) / 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
              if (data.largestExpense != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: const Text('Largest expense'),
                    subtitle: Text(data.largestExpense!.title),
                    trailing: Text(
                      Money(
                        data.largestExpense!.totalAmountPaise,
                      ).formatCompact(),
                    ),
                  ),
                ),
              const SizedBox(height: AppConstants.spaceLg),
              Text(
                'My spending by category',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _Breakdown(data: data.categoryTotals),
              const SizedBox(height: AppConstants.spaceLg),
              Text(
                'My monthly spending',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              data.monthTotals.length < 2
                  ? const _TrendEmptyState()
                  : _TrendChart(monthTotals: data.monthTotals),
              const SizedBox(height: AppConstants.spaceLg),
              Text(
                'My spending by group',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _Breakdown(data: data.groupTotals),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, {required this.width});
  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppConstants.spaceXs),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.data});
  final Map<String, int> data;

  @override
  Widget build(BuildContext context) {
    final ordered = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = ordered.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Column(
          children: ordered
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(item.key)),
                          Text(Money(item.value).formatCompact()),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: item.value / max,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.monthTotals});
  final Map<DateTime, int> monthTotals;

  @override
  Widget build(BuildContext context) {
    final entries = monthTotals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final max = entries
        .map((entry) => entry.value)
        .reduce((a, b) => a > b ? a : b);
    return Card(
      child: SizedBox(
        height: 180,
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: entries
                .map(
                  (entry) => Expanded(
                    child: Semantics(
                      label:
                          '${entry.key.month}/${entry.key.year}: ${Money(entry.value).formatCompact()}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: entry.value / max,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${entry.key.month}/${entry.key.year.toString().substring(2)}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppConstants.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insights_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppConstants.spaceMd),
          Text(
            'Your spending story starts here',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppConstants.spaceSm),
          const Text(
            'Add a few expenses to see your own spending, shares, and trends.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _TrendEmptyState extends StatelessWidget {
  const _TrendEmptyState();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      child: Row(
        children: [
          Icon(
            Icons.show_chart_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppConstants.spaceMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not enough data yet'),
                SizedBox(height: 4),
                Text(
                  'Add expenses across a few months to see your spending trend.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
