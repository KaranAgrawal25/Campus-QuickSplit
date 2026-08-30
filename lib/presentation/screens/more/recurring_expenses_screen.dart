import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/expense_providers.dart';

class RecurringExpensesScreen extends ConsumerWidget {
  const RecurringExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref
        .watch(recurringExpenseRepositoryProvider)
        .watchTemplates();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring expenses'),
        actions: [
          TextButton(
            onPressed: () async {
              final count = await ref
                  .read(recurringExpenseRepositoryProvider)
                  .generateDue();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      count == 0
                          ? 'No recurring expenses are due'
                          : 'Added $count due expense${count == 1 ? '' : 's'}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Generate due'),
          ),
        ],
      ),
      body: StreamBuilder<List<RecurringExpenseTemplate>>(
        stream: templates,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No recurring templates yet. Create one from an expense.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _TemplateTile(template: items[index]),
          );
        },
      ),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template});
  final RecurringExpenseTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: ref
        .read(expenseRepositoryProvider)
        .details(template.sourceExpenseId),
    builder: (context, snapshot) {
      final title =
          snapshot.data?.expense.title ?? 'Original expense unavailable';
      return Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Icon(
              template.isActive ? Icons.repeat : Icons.pause_circle_outline,
            ),
          ),
          title: Text(title),
          subtitle: Text(
            '${template.intervalDays == 30 ? 'Monthly' : 'Every ${template.intervalDays} days'} · Next due ${DateFormat('d MMM').format(template.nextDueAt.toLocal())}',
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              final repository = ref.read(recurringExpenseRepositoryProvider);
              if (action == 'toggle') {
                await repository.setActive(template.id, !template.isActive);
              }
              if (action == 'stop') {
                await repository.stop(template.id);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle',
                child: Text(template.isActive ? 'Pause' : 'Resume'),
              ),
              const PopupMenuItem(value: 'stop', child: Text('Stop')),
            ],
          ),
        ),
      );
    },
  );
}
