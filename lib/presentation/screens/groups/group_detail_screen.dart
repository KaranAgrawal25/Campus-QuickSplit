import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../providers/expense_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/group_providers.dart';
import '../../providers/user_providers.dart';
import '../payments/payment_screen.dart';
import '../expenses/add_expense_screen.dart';
import '../expenses/expense_detail_screen.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddMemberDialog(),
    );
    if (name == null || !context.mounted) return;
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser == null) {
        throw StateError('Your local user is unavailable');
      }
      await ref
          .read(groupRepositoryProvider)
          .addMember(groupId, name, currentUserId: currentUser.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _renameGroup(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Rename group'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Group name'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name == null || !context.mounted) return;
      await ref.read(groupRepositoryProvider).rename(groupId, name);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not rename group')));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _deleteExpenseWithUndo(
    BuildContext context,
    WidgetRef ref,
    String expenseId,
  ) async {
    try {
      final repository = ref.read(expenseRepositoryProvider);
      await repository.delete(expenseId);
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Expense deleted'),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () async {
                try {
                  await repository.restore(expenseId);
                } on StateError {
                  // A later action already changed this expense. Streams show
                  // the current persisted state instead of restoring twice.
                }
              },
            ),
          ),
        );
      return true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete expense')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(groupProvider(groupId));
    final expenses = ref.watch(groupExpensesProvider(groupId));
    final settlements = ref.watch(groupSettlementSuggestionsProvider(groupId));
    final summary = ref.watch(groupFinancialSummaryProvider(groupId));
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
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename group',
                onPressed: () => _renameGroup(context, ref, data.group.name),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_2),
                tooltip: 'Invite',
                onPressed: () async {
                  try {
                    throw StateError(
                      'Secure cross-account invitations are not available yet. '
                      'Cloud sync remains private to your signed-in account.',
                    );
                  } on StateError catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.message.toString())),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not create invitation'),
                        ),
                      );
                    }
                  }
                },
              ),
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
                  if (confirmed == true && context.mounted) {
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
              summary.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
                data: (value) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spaceLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total spent',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Money(value.totalSpentPaise).formatCompact(),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Divider(height: AppConstants.spaceLg * 2),
                        Wrap(
                          spacing: AppConstants.spaceLg,
                          runSpacing: AppConstants.spaceSm,
                          children: [
                            _SummaryValue(
                              'You paid',
                              value.yourContributionPaise,
                            ),
                            _SummaryValue('Your share', value.yourSharePaise),
                            _SummaryValue(
                              value.netBalancePaise >= 0
                                  ? 'You are owed'
                                  : 'You owe',
                              value.netBalancePaise.abs(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
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
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: data.members.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final user = data.members[index];
                    return Semantics(
                      label: user.isCurrentUser
                          ? '${user.name}, you'
                          : user.name,
                      child: SizedBox(
                        width: 56,
                        child: Column(
                          children: [
                            CircleAvatar(child: Text(user.initials)),
                            const SizedBox(height: 4),
                            Text(
                              user.isCurrentUser
                                  ? 'You'
                                  : user.name.split(' ').first,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppConstants.spaceLg),
              Text('Settle up', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              settlements.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Could not load settlement suggestions.'),
                  ),
                ),
                data: (suggestions) {
                  final currentUser = ref
                      .watch(currentUserProvider)
                      .valueOrNull;
                  final membersById = {
                    for (final member in data.members) member.id: member,
                  };
                  final payable = suggestions
                      .where(
                        (suggestion) =>
                            suggestion.fromUserId == currentUser?.id,
                      )
                      .toList();
                  if (payable.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('You are all settled up in this group.'),
                      ),
                    );
                  }
                  return Column(
                    children: payable.map((suggestion) {
                      final recipient = membersById[suggestion.toUserId];
                      if (recipient == null) return const SizedBox.shrink();
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(child: Text(recipient.initials)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('You owe ${recipient.name}'),
                                    const SizedBox(height: 4),
                                    Text(
                                      Money(
                                        suggestion.amountPaise,
                                      ).formatCompact(),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: () async {
                                  final recorded = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PaymentScreen(
                                        recipient: recipient,
                                        suggestion: suggestion,
                                      ),
                                    ),
                                  );
                                  if (recorded == true && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Settlement recorded: ${Money(suggestion.amountPaise).formatCompact()} paid to ${recipient.name}.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Pay'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: AppConstants.spaceLg),
              Text('Expenses', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              expenses.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('$e'),
                data: (items) => items.isEmpty
                    ? const _NoExpensesCard()
                    : Column(
                        children: items
                            .map(
                              (expense) => Dismissible(
                                key: ValueKey('expense-${expense.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: Theme.of(context).colorScheme.error,
                                  child: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onError,
                                  ),
                                ),
                                confirmDismiss: (_) => _deleteExpenseWithUndo(
                                  context,
                                  ref,
                                  expense.id,
                                ),
                                child: Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.receipt_long_outlined),
                                    ),
                                    title: Text(expense.title),
                                    subtitle: Text(
                                      _friendlyDate(expense.createdAt),
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
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'group-$groupId-add-expense',
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

String _friendlyDate(DateTime value) {
  final date = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Today · ${DateFormat.jm().format(date)}';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('d MMM').format(date);
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue(this.label, this.amountPaise);
  final String label;
  final int amountPaise;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 130,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          Money(amountPaise).formatCompact(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _NoExpensesCard extends StatelessWidget {
  const _NoExpensesCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppConstants.spaceLg),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            child: Icon(
              Icons.receipt_long_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppConstants.spaceMd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No expenses yet'),
                SizedBox(height: 4),
                Text('Add the first expense to start tracking this group.'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Owns the input controller for the lifetime of the dialog route. The group
/// screen only receives a validated value after this route has been popped.
class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add member'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: 'Name'),
        validator: (value) =>
            value?.trim().isEmpty ?? true ? 'Enter a member name' : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Add')),
    ],
  );
}
