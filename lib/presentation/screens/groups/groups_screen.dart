import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money.dart';
import '../../../data/database/app_database.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/group_providers.dart';
import '../../providers/user_providers.dart';
import '../../widgets/app_ui.dart';
import 'group_detail_screen.dart';
import 'scan_invite_screen.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final members = TextEditingController();
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser == null) return;
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _CreateGroupSheet(
          name: name,
          members: members,
          currentUserName: currentUser.name,
          currentUserInitials: currentUser.initials,
        ),
      );
      if (result != true || !context.mounted) return;
      final id = await ref
          .read(groupRepositoryProvider)
          .createGroup(
            name: name.text,
            currentUserId: currentUser.id,
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
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Archived groups',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchivedGroupsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan QR',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScanInviteScreen()),
            ),
          ),
        ],
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Could not load groups. Please try again.'),
        ),
        data: (items) => items.isEmpty
            ? _EmptyGroups(onCreate: () => _create(context, ref))
            : ListView.separated(
                padding: const EdgeInsets.all(AppConstants.spaceMd),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppConstants.spaceSm),
                itemBuilder: (context, index) {
                  final group = items[index];
                  return _GroupCard(group: group);
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'groups-new-group',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New group'),
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group});
  final Group group;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(groupFinancialSummaryProvider(group.id));
    final details = ref.watch(groupProvider(group.id));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupDetailScreen(groupId: group.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(group.name.substring(0, 1).toUpperCase()),
              ),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    summary.when(
                      loading: () => const Text('Updating group summary…'),
                      error: (_, __) => const Text('Open to view expenses'),
                      data: (data) {
                        final amount = Money(
                          data.netBalancePaise.abs(),
                        ).formatCompact();
                        final memberCount = details.valueOrNull?.members.length;
                        final countLabel = memberCount == null
                            ? ''
                            : '$memberCount member${memberCount == 1 ? '' : 's'} · ';
                        final statusColor = data.netBalancePaise < 0
                            ? Theme.of(context).colorScheme.error
                            : data.netBalancePaise > 0
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$countLabel${Money(data.totalSpentPaise).formatCompact()} spent',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              data.netBalancePaise < 0
                                  ? 'You owe $amount'
                                  : data.netBalancePaise > 0
                                  ? 'You are owed $amount'
                                  : 'You’re settled up',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class ArchivedGroupsScreen extends ConsumerWidget {
  const ArchivedGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(archivedGroupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Archived groups')),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load archived groups.')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('No archived groups.'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final group = items[index];
                  return ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(group.name),
                    subtitle: const Text('Expenses are preserved'),
                    trailing: TextButton(
                      onPressed: () async {
                        await ref
                            .read(groupRepositoryProvider)
                            .restore(group.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Group restored')),
                          );
                        }
                      },
                      child: const Text('Restore'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => AppEmptyState(
    icon: Icons.groups_2_outlined,
    title: 'No groups yet',
    message: 'Create a group to start splitting expenses with friends.',
    actionLabel: 'Create your first group',
    onAction: onCreate,
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.name,
    required this.members,
    required this.currentUserName,
    required this.currentUserInitials,
  });
  final TextEditingController name;
  final TextEditingController members;
  final String currentUserName, currentUserInitials;
  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _member = TextEditingController();
  final _names = <String>[];
  String? _error;
  @override
  void dispose() {
    _member.dispose();
    super.dispose();
  }

  void _add() {
    final value = _member.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return;
    if (_names.any((name) => name.toLowerCase() == value.toLowerCase())) {
      setState(() => _error = 'That member is already added.');
      return;
    }
    setState(() {
      _names.add(value);
      _member.clear();
      _error = null;
    });
  }

  void _submit() {
    if (widget.name.text.trim().isEmpty) {
      setState(() => _error = 'Give your group a name first.');
      return;
    }
    widget.members.text = _names.join(',');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spaceLg,
        AppConstants.spaceSm,
        AppConstants.spaceLg,
        MediaQuery.viewInsetsOf(context).bottom + AppConstants.spaceLg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppConstants.spaceLg),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(
              'Create a group',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              'Start with yourself, then add the people you split with.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            TextField(
              controller: widget.name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'e.g. Goa trip',
              ),
            ),
            const SizedBox(height: AppConstants.spaceLg),
            Text('Members', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(widget.currentUserInitials)),
              title: Text(widget.currentUserName),
              subtitle: const Text('You'),
              trailing: Icon(
                Icons.check_circle_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            if (_names.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _names
                    .map(
                      (name) => InputChip(
                        label: Text(name),
                        onDeleted: () => setState(() => _names.remove(name)),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _member,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(hintText: 'Add a member'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add member',
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: AppConstants.spaceLg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppConstants.spaceSm),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Create group'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
