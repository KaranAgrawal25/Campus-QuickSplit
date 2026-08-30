import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/money.dart';
import '../../../data/repositories/activity_repository.dart';
import '../../providers/expense_providers.dart';
import '../../widgets/app_ui.dart';
import '../expenses/expense_detail_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(recentActivityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: activity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Could not load activity. Please try again.'),
        ),
        data: (items) {
          final query = _search.text.trim().toLowerCase();
          final filtered = items.where((entry) {
            if (_filter == 'Expenses' && entry.expense == null) return false;
            if (_filter == 'Settlements' && entry.settlement == null) {
              return false;
            }
            if (query.isEmpty) return true;
            return entry.searchableText.toLowerCase().contains(query);
          }).toList();
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No activity yet',
              message: 'Expenses and settlements will appear here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search expenses, groups, people or amount',
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: ['All', 'Expenses', 'Settlements']
                      .map(
                        (label) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _filter == label,
                            onSelected: (_) => setState(() => _filter = label),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No activity matches your search.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ..._timeline(context, filtered),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _timeline(BuildContext context, List<ActivityEntry> entries) {
    final widgets = <Widget>[];
    String? lastDay;
    for (final entry in entries) {
      final date = entry.occurredAt.toLocal();
      final day = _dayLabel(date);
      if (day != lastDay) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            child: Text(
              day,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
        lastDay = day;
      }
      widgets.add(
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                entry.expense != null
                    ? _categoryIcon(entry.expense!.category)
                    : Icons.payments_outlined,
              ),
            ),
            title: Text(entry.expense?.title ?? 'Settlement recorded'),
            subtitle: Text(_subtitleFor(entry, date)),
            isThreeLine: true,
            trailing: Text(
              Money(
                entry.expense?.totalAmountPaise ??
                    entry.settlement!.amountPaise,
              ).formatCompact(),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            onTap: entry.expense == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ExpenseDetailScreen(expenseId: entry.expense!.id),
                    ),
                  ),
          ),
        ),
      );
    }
    return widgets;
  }
}

String _subtitleFor(ActivityEntry entry, DateTime date) {
  final group = entry.groupName == 'Unknown group' ? 'Group' : entry.groupName;
  final actor = entry.actorName == 'Unknown member'
      ? 'a group member'
      : entry.actorName;
  final action = entry.expense == null
      ? 'Settlement recorded by $actor'
      : actor == 'a group member'
      ? 'Paid by $actor'
      : '$actor paid';
  final category = entry.expense?.category;
  return '${category == null ? action : '$category · $action'}\n$group · ${DateFormat.jm().format(date)}';
}

String _dayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final value = DateTime(date.year, date.month, date.day);
  if (value == today) return 'Today';
  if (value == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('d MMM').format(date);
}

IconData _categoryIcon(String category) => switch (category) {
  'Food' => Icons.restaurant_outlined,
  'Transport' => Icons.directions_bus_outlined,
  'Rent' => Icons.home_outlined,
  'Hotel' => Icons.hotel_outlined,
  'Education' => Icons.school_outlined,
  'Shopping' => Icons.shopping_bag_outlined,
  'Subscriptions' => Icons.subscriptions_outlined,
  'Entertainment' => Icons.movie_outlined,
  'Utilities' => Icons.bolt_outlined,
  'Medical' => Icons.medical_services_outlined,
  'Travel' => Icons.flight_outlined,
  _ => Icons.receipt_long_outlined,
};
