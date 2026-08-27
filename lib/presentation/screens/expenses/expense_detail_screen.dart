import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/money.dart';
import '../../providers/expense_providers.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});
  final String expenseId;
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
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(expenseRepositoryProvider).delete(expenseId);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              data.expense.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              Money(data.expense.totalAmountPaise).format(),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Group'),
              trailing: Text(data.group.name),
            ),
            ListTile(
              title: const Text('Paid by'),
              trailing: Text(data.payer.name),
            ),
            ListTile(
              title: const Text('Split'),
              trailing: Text(data.expense.splitType.name),
            ),
            ListTile(
              title: const Text('Date'),
              trailing: Text(
                data.expense.createdAt.toLocal().toString().split('.').first,
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
