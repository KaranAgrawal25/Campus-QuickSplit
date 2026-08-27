import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../providers/expense_providers.dart';
import '../../providers/group_providers.dart';
import '../expenses/add_expense_screen.dart';
import '../expenses/expense_detail_screen.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final okay = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (okay == true) {
      try {
        await ref
            .read(groupRepositoryProvider)
            .addMember(groupId, controller.text);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(groupProvider(groupId));
    final expenses = ref.watch(groupExpensesProvider(groupId));
    return detail.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (data) {
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('This group is unavailable')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(data.group.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive group',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Archive group?'),
                      content: const Text(
                        'Its expenses and settlement history will be kept, but it will be hidden from active groups.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Archive'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(groupRepositoryProvider).archive(groupId);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppConstants.spaceMd),
            children: [
              Row(
                children: [
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _addMember(context, ref),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add'),
                  ),
                ],
              ),
              ...data.members.map(
                (user) => ListTile(
                  leading: CircleAvatar(child: Text(user.initials)),
                  title: Text(user.name),
                  subtitle: user.isCurrentUser ? const Text('You') : null,
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
              Text('Expenses', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              expenses.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
                data: (items) => items.isEmpty
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No expenses yet. Add the first one.'),
                        ),
                      )
                    : Column(
                        children: items
                            .map(
                              (expense) => Card(
                                child: ListTile(
                                  title: Text(expense.title),
                                  subtitle: Text(
                                    expense.createdAt
                                        .toLocal()
                                        .toString()
                                        .split(' ')
                                        .first,
                                  ),
                                  trailing: Text(
                                    Money(
                                      expense.totalAmountPaise,
                                    ).formatCompact(),
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ExpenseDetailScreen(
                                        expenseId: expense.id,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddExpenseScreen(groupId: groupId),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Expense'),
          ),
        );
      },
    );
  }
}
