import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../providers/group_providers.dart';
import '../../providers/user_providers.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final members = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: members,
              decoration: const InputDecoration(
                labelText: 'Members (comma separated)',
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      final id = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            name: name.text,
            currentUserId: user.id,
            memberNames: members.text.split(','),
          );
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: id)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      name.dispose();
      members.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load groups: $error')),
        data: (items) => items.isEmpty
            ? const _EmptyGroups()
            : ListView.separated(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppConstants.spaceSm),
                itemBuilder: (context, index) {
                  final group = items[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(group.name.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(group.name),
                      subtitle: const Text(
                        'Tap to manage members and expenses',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailScreen(groupId: group.id),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New group'),
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups_2_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('Start a group', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Create a group for your flat, trip, or class and add the people who split costs with you.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
