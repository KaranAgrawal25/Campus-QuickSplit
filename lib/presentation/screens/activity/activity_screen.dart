import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/money.dart';
import '../../providers/expense_providers.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(recentExpensesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: expenses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No activity yet\nExpenses and settlements will appear here.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Recent expenses'),
              ),
              ...items.map(
                (e) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text(e.title),
                  subtitle: Text(
                    e.createdAt.toLocal().toString().split('.').first,
                  ),
                  trailing: Text(Money(e.totalAmountPaise).formatCompact()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
