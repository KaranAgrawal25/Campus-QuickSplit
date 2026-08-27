import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/finance/split_engine.dart';
import '../../providers/expense_providers.dart';
import '../../providers/group_providers.dart';
import '../../../data/database/tables.dart';
import '../../../data/repositories/expense_repository.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.groupId});
  final String groupId;
  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  SplitTypeDb _type = SplitTypeDb.equal;
  String? _payerId;
  final _selected = <String>{};
  final _ratios = <String, TextEditingController>{};
  final _custom = <String, TextEditingController>{};
  bool _saving = false;
  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _description.dispose();
    for (final c in [..._ratios.values, ..._custom.values]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _paise(String input) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,2}))?\s*$').firstMatch(input);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 100 +
        int.parse((match.group(2) ?? '').padRight(2, '0'));
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final amount = _paise(_amount.text)!;
    final ids = _selected.toList()..sort();
    try {
      List<SplitShare> shares;
      if (_type == SplitTypeDb.equal) {
        shares = SplitEngine.equal(totalPaise: amount, userIds: ids);
      } else if (_type == SplitTypeDb.ratio) {
        shares = SplitEngine.ratio(
          totalPaise: amount,
          userIds: ids,
          ratios: ids
              .map((id) => int.tryParse(_ratios[id]?.text ?? '') ?? 0)
              .toList(),
        );
      } else {
        shares = SplitEngine.custom(
          totalPaise: amount,
          shares: ids
              .map(
                (id) => SplitShare(
                  userId: id,
                  amountPaise: _paise(_custom[id]?.text ?? '') ?? 0,
                ),
              )
              .toList(),
        );
      }
      setState(() => _saving = true);
      await ref
          .read(expenseRepositoryProvider)
          .create(
            ExpenseDraft(
              groupId: widget.groupId,
              title: _title.text,
              description: _description.text,
              totalAmountPaise: amount,
              payerId: _payerId!,
              participants: shares,
              splitType: _type,
              date: DateTime.now(),
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(groupProvider(widget.groupId));
    return group.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (data) {
        if (data == null) {
          return const Scaffold(body: Center(child: Text('Group unavailable')));
        }
        final members = data.members;
        _payerId ??= members.isNotEmpty ? members.first.id : null;
        _selected.addAll(members.map((m) => m.id));
        for (final member in members) {
          _ratios.putIfAbsent(
            member.id,
            () => TextEditingController(text: '1'),
          );
          _custom.putIfAbsent(member.id, TextEditingController.new);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Add expense')),
          body: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'What was it for?',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a title'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) =>
                      _paise(value ?? '') == null || _paise(value ?? '')! <= 0
                      ? 'Enter a positive amount with up to 2 decimals'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _payerId,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: members
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.isCurrentUser ? '${m.name} (You)' : m.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _payerId = value),
                ),
                const SizedBox(height: 20),
                Text(
                  'Split between',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...members.map(
                  (m) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(m.id),
                    title: Text(m.isCurrentUser ? '${m.name} (You)' : m.name),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected.add(m.id);
                      } else {
                        _selected.remove(m.id);
                      }
                    }),
                  ),
                ),
                if (_selected.isEmpty)
                  const Text(
                    'Select at least one participant',
                    style: TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 12),
                SegmentedButton<SplitTypeDb>(
                  segments: const [
                    ButtonSegment(
                      value: SplitTypeDb.equal,
                      label: Text('Equal'),
                    ),
                    ButtonSegment(
                      value: SplitTypeDb.ratio,
                      label: Text('Ratio'),
                    ),
                    ButtonSegment(
                      value: SplitTypeDb.specificAmount,
                      label: Text('Custom'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) =>
                      setState(() => _type = value.first),
                ),
                if (_type != SplitTypeDb.equal) ...[
                  const SizedBox(height: 12),
                  ...members
                      .where((m) => _selected.contains(m.id))
                      .map(
                        (m) => TextFormField(
                          controller: _type == SplitTypeDb.ratio
                              ? _ratios[m.id]
                              : _custom[m.id],
                          decoration: InputDecoration(
                            labelText: _type == SplitTypeDb.ratio
                                ? 'Ratio for ${m.name}'
                                : 'Amount for ${m.name} (₹)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving || _selected.isEmpty ? null : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Save expense'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
