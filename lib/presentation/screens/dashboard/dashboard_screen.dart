import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../data/database/app_database.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/expense_providers.dart';
import '../../providers/group_providers.dart';
import '../../providers/user_providers.dart';
import '../expenses/add_expense_screen.dart';
import '../activity/activity_screen.dart';
import '../groups/groups_screen.dart';
import '../groups/group_detail_screen.dart';
import '../groups/scan_invite_screen.dart';
import '../payments/payment_screen.dart';
import '../../widgets/app_ui.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _addExpense(BuildContext context, WidgetRef ref) async {
    final groups = await ref.read(groupsProvider.future);
    if (!context.mounted) return;
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a group before adding an expense.'),
        ),
      );
      return;
    }
    String? groupId = groups.length == 1
        ? groups.first.id
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Choose a group')),
                  ...groups.map(
                    (group) => ListTile(
                      leading: CircleAvatar(
                        child: Text(group.name.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(group.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, group.id),
                    ),
                  ),
                ],
              ),
            ),
          );
    if (groupId != null && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AddExpenseScreen(groupId: groupId)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final analyticsAsync = ref.watch(analyticsSummaryProvider);
    final activityAsync = ref.watch(recentActivityProvider);
    final groupsAsync = ref.watch(groupsProvider);

    final name = userAsync.valueOrNull?.name.split(' ').first ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppConstants.spaceMd),
            child: _BrandMark(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardSummaryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          children: [
            Text(
              '${_greeting()}${name.isEmpty ? '' : ', $name'}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              'Here’s your money at a glance.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            summaryAsync.when(
              data: (summary) => _BalanceCards(summary: summary),
              loading: () => const _BalanceCardsSkeleton(),
              error: (_, __) => const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppConstants.spaceMd),
                  child: Text('Could not load balances. Please try again.'),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            const _NeedsAttention(),
            const SizedBox(height: AppConstants.spaceLg),
            const AppSectionHeader(title: 'Quick actions'),
            const SizedBox(height: AppConstants.spaceSm),
            _QuickActions(
              onAddExpense: () => _addExpense(context, ref),
              onNewGroup: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupsScreen()),
              ),
              onScanQr: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanInviteScreen()),
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            analyticsAsync.when(
              data: (summary) => Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Total group spending'),
                  subtitle: const Text('Across your active groups'),
                  trailing: Text(
                    Money(summary.totalSpentPaise).formatCompact(),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            AppSectionHeader(
              title: 'Recent activity',
              actionLabel: 'View all',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivityScreen()),
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            activityAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const _EmptyActivityState(),
              data: (items) => items.isEmpty
                  ? const _EmptyActivityState()
                  : Card(
                      child: Column(
                        children: items
                            .take(3)
                            .map(
                              (entry) => ListTile(
                                leading: Icon(
                                  entry.expense == null
                                      ? Icons.payments_outlined
                                      : Icons.receipt_long_outlined,
                                ),
                                title: Text(
                                  entry.expense?.title ?? 'Settlement recorded',
                                ),
                                trailing: Text(
                                  Money(
                                    entry.expense?.totalAmountPaise ??
                                        entry.settlement!.amountPaise,
                                  ).formatCompact(),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            AppSectionHeader(
              title: 'Your groups',
              actionLabel: 'View all',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupsScreen()),
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            groupsAsync.when(
              loading: () => const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (groups) => groups.isEmpty
                  ? const Text('Create a group to begin splitting expenses.')
                  : _GroupOverview(groups: groups.take(3).toList()),
            ),
            const SizedBox(height: AppConstants.spaceXl),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboard-add-expense',
        onPressed: () => _addExpense(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }
}

class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null || groups.valueOrNull == null) {
      return const SizedBox.shrink();
    }
    final cards = <Widget>[];
    for (final group in groups.value!) {
      final suggestions = ref
          .watch(groupSettlementSuggestionsProvider(group.id))
          .valueOrNull;
      final detail = ref.watch(groupProvider(group.id)).valueOrNull;
      if (suggestions == null || detail == null) continue;
      for (final suggestion in suggestions.where(
        (item) => item.fromUserId == user.id,
      )) {
        final recipient = detail.members
            .where((member) => member.id == suggestion.toUserId)
            .firstOrNull;
        if (recipient == null) continue;
        cards.add(
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: CircleAvatar(child: Text(recipient.initials)),
              title: const Text('Needs your attention'),
              subtitle: Text('You owe ${recipient.name} · ${group.name}'),
              trailing: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                      recipient: recipient,
                      suggestion: suggestion,
                    ),
                  ),
                ),
                child: Text(
                  'Pay ${Money(suggestion.amountPaise).formatCompact()}',
                ),
              ),
            ),
          ),
        );
        break;
      }
      if (cards.isNotEmpty) break;
    }
    return cards.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Needs your attention',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppConstants.spaceSm),
              ...cards,
            ],
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

    final youOwe = net.isNegative;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your balance',
              style: theme.textTheme.labelLarge?.copyWith(
                color: youOwe
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              '${youOwe ? '-' : '+'}${net.abs().formatCompact()}',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: youOwe
                    ? AppTheme.negativeBalance
                    : AppTheme.positiveBalance,
              ),
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              youOwe
                  ? 'You owe across your groups'
                  : net.isZero
                  ? 'You’re all settled up'
                  : 'You are owed across your groups',
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(height: AppConstants.spaceLg * 2),
            Row(
              children: [
                Expanded(
                  child: _BalanceChip(
                    label: 'You owe',
                    amount: owe,
                    color: AppTheme.negativeBalance,
                  ),
                ),
                Container(
                  width: 1,
                  height: 42,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _BalanceChip(
                    label: 'You are owed',
                    amount: owed,
                    color: AppTheme.positiveBalance,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddExpense,
    required this.onNewGroup,
    required this.onScanQr,
  });
  final VoidCallback onAddExpense;
  final VoidCallback onNewGroup;
  final VoidCallback onScanQr;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _QuickAction(
          icon: Icons.add_card_outlined,
          label: 'Add expense',
          onTap: onAddExpense,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _QuickAction(
          icon: Icons.group_add_outlined,
          label: 'New group',
          onTap: onNewGroup,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _QuickAction(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Scan QR',
          onTap: onScanQr,
        ),
      ),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _GroupOverview extends ConsumerWidget {
  const _GroupOverview({required this.groups});
  final List<Group> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Column(
      children: groups.map((group) {
        final summary = ref.watch(groupFinancialSummaryProvider(group.id));
        final members = ref.watch(groupProvider(group.id));
        final spending = summary.valueOrNull == null
            ? 'Updating spending…'
            : '${Money(summary.value!.totalSpentPaise).formatCompact()} spent';
        final memberCount = members.valueOrNull?.members.length;
        return ListTile(
          leading: CircleAvatar(child: Text(group.name[0].toUpperCase())),
          title: Text(group.name),
          subtitle: Text(
            '${memberCount == null ? '' : '$memberCount member${memberCount == 1 ? '' : 's'} · '}$spending',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: group.id),
            ),
          ),
        );
      }).toList(),
    ),
  );
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spaceXs),
          Text(
            amount.formatCompact(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Campus QuickSplit',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const SizedBox(
        width: 32,
        height: 32,
        child: Icon(Icons.call_split_rounded, size: 19, color: Colors.white),
      ),
    ),
  );
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
