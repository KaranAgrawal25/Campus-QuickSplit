import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/money.dart';
import '../../providers/expense_providers.dart';
import '../../providers/database_provider.dart';
import 'add_expense_screen.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});
  final String expenseId;

  Future<void> _createRecurring(BuildContext context, WidgetRef ref) async {
    int? interval;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Make recurring'),
        content: const Text(
          'Each due instance will be created only when you choose Generate due in Recurring expenses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'weekly'),
            child: const Text('Weekly'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'monthly'),
            child: const Text('Monthly'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    interval = choice == 'weekly' ? 7 : 30;
    try {
      await ref
          .read(recurringExpenseRepositoryProvider)
          .create(
            sourceExpenseId: expenseId,
            intervalDays: interval,
            firstDueAt: DateTime.now().add(Duration(days: interval)),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recurring template created')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Could not create recurring template',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: ref.read(expenseRepositoryProvider).details(expenseId),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final data = snapshot.data;
      if (data == null) {
        return const Scaffold(body: Center(child: Text('Expense unavailable')));
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Expense details'),
          actions: [
            IconButton(
              icon: const Icon(Icons.repeat),
              tooltip: 'Make recurring',
              onPressed: () => _createRecurring(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddExpenseScreen(
                    groupId: data.group.id,
                    expenseId: expenseId,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete expense',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Delete expense?'),
                    content: const Text(
                      'This expense will be removed from balances. You can undo this action.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                final repository = ref.read(expenseRepositoryProvider);
                try {
                  await repository.delete(expenseId);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Expense deleted'),
                      action: SnackBarAction(
                        label: 'UNDO',
                        onPressed: () async {
                          try {
                            await repository.restore(expenseId);
                          } catch (_) {
                            // The item may have been changed by a later
                            // action. The next screen refresh shows the truth.
                          }
                        },
                      ),
                    ),
                  );
                  Navigator.pop(context);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not delete expense')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          child: Icon(
                            _expenseIcon(data.expense.category),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          data.expense.category.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                letterSpacing: 1,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.expense.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Money(data.expense.totalAmountPaise).formatCompact(),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Group'),
              trailing: Text(data.group.name),
            ),
            ListTile(
              title: const Text('Category'),
              trailing: Text(data.expense.category),
            ),
            ...data.payments.map(
              (item) => ListTile(
                title: Text(
                  data.payments.length == 1 ? 'Paid by' : 'Payment by',
                ),
                subtitle: Text(item.user.name),
                trailing: Text(Money(item.payment.amountPaidPaise).format()),
              ),
            ),
            ListTile(
              title: const Text('Split'),
              trailing: Text(data.expense.splitType.name),
            ),
            if (data.expense.description != null)
              ListTile(
                title: const Text('Note'),
                subtitle: Text(data.expense.description!),
              ),
            if (data.expense.receiptPath != null &&
                File(data.expense.receiptPath!).existsSync())
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  label: 'Receipt image',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(data.expense.receiptPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ListTile(
              title: const Text('Date'),
              trailing: Text(
                DateFormat(
                  'd MMM yyyy · h:mm a',
                ).format(data.expense.createdAt.toLocal()),
              ),
            ),
            const Divider(),
            Text('Shares', style: Theme.of(context).textTheme.titleMedium),
            ...data.shares.map(
              (item) => ListTile(
                title: Text(item.user.name),
                trailing: Text(Money(item.share.amountOwedPaise).format()),
              ),
            ),
          ],
        ),
      );
    },
  );
}

IconData _expenseIcon(String category) => switch (category) {
  'Food' => Icons.restaurant_outlined,
  'Transport' => Icons.directions_car_outlined,
  'Shopping' => Icons.shopping_bag_outlined,
  'Entertainment' => Icons.movie_outlined,
  'Subscriptions' => Icons.subscriptions_outlined,
  _ => Icons.receipt_long_outlined,
};
