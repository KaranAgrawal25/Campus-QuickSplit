import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/finance/split_engine.dart';
import '../../../core/utils/money.dart';
import '../../providers/expense_providers.dart';
import '../../providers/group_providers.dart';
import '../../../data/database/tables.dart';
import '../../../data/repositories/expense_repository.dart';

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({super.key, required this.groupId, this.expenseId});
  final String groupId;
  final String? expenseId;
  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  SplitTypeDb _type = SplitTypeDb.equal;
  String _category = 'Other';
  String? _payerId;
  final _selected = <String>{};
  final _ratios = <String, TextEditingController>{};
  final _percentages = <String, TextEditingController>{};
  final _custom = <String, TextEditingController>{};
  final _paymentAmounts = <String, TextEditingController>{};
  final _paymentPayerIds = <String>{};
  bool _hasMultiplePayers = false;
  bool _saving = false;
  bool _participantsInitialized = false;
  late bool _loadedExisting = widget.expenseId == null;
  DateTime _date = DateTime.now();
  String? _loadError;
  String? _receiptPath;

  @override
  void initState() {
    super.initState();
    if (widget.expenseId != null) _loadExisting();
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _description.dispose();
    for (final c in [
      ..._ratios.values,
      ..._percentages.values,
      ..._custom.values,
      ..._paymentAmounts.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _paise(String input) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,2}))?\s*$').firstMatch(input);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    final fraction = int.tryParse((match.group(2) ?? '').padRight(2, '0'));
    if (whole == null || fraction == null) return null;
    return whole * 100 + fraction;
  }

  String _rupees(int paise) {
    final whole = paise ~/ 100;
    final fraction = paise % 100;
    return fraction == 0
        ? '$whole'
        : '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  String? _allocationStatus() {
    if (_type == SplitTypeDb.equal || _selected.isEmpty) return null;
    if (_type == SplitTypeDb.percentage) {
      final allocated = _selected.fold<int>(
        0,
        (sum, id) => sum + (int.tryParse(_percentages[id]?.text ?? '') ?? 0),
      );
      return allocated == 100
          ? 'Allocated: 100%'
          : 'Allocated: $allocated% · Remaining: ${100 - allocated}%';
    }
    if (_type == SplitTypeDb.ratio) {
      final total = _selected.fold<int>(
        0,
        (sum, id) => sum + (int.tryParse(_ratios[id]?.text ?? '') ?? 0),
      );
      return total > 0
          ? 'Total ratio: $total'
          : 'Add at least one positive ratio';
    }
    final allocated = _selected.fold<int>(
      0,
      (sum, id) => sum + (_paise(_custom[id]?.text ?? '') ?? 0),
    );
    final total = _paise(_amount.text) ?? 0;
    final difference = total - allocated;
    return difference == 0
        ? 'Allocated: ${Money(allocated).formatCompact()}'
        : 'Allocated: ${Money(allocated).formatCompact()} · Remaining: ${Money(difference.abs()).formatCompact()}${difference < 0 ? ' over' : ''}';
  }

  String? _paymentValidationMessage() {
    if (!_hasMultiplePayers) return null;
    if (_paymentPayerIds.isEmpty) return 'Select at least one payer';
    final amounts = _paymentPayerIds
        .map((id) => _paise(_paymentAmounts[id]?.text ?? ''))
        .toList();
    if (amounts.any((amount) => amount == null || amount <= 0)) {
      return 'Enter a positive amount for every selected payer';
    }
    final total = _paise(_amount.text);
    if (total == null || total <= 0) return null;
    final paid = amounts.cast<int>().fold<int>(
      0,
      (sum, amount) => sum + amount,
    );
    if (paid != total) {
      return paid > total
          ? 'Payer amounts exceed the expense total'
          : 'Payer amounts are ${Money(total - paid).formatCompact()} short';
    }
    return null;
  }

  Future<void> _loadExisting() async {
    try {
      final details = await ref
          .read(expenseRepositoryProvider)
          .details(widget.expenseId!);
      if (!mounted) return;
      if (details == null) {
        setState(() => _loadError = 'Expense unavailable');
        return;
      }
      setState(() {
        _title.text = details.expense.title;
        _amount.text = _rupees(details.expense.totalAmountPaise);
        _description.text = details.expense.description ?? '';
        _type = details.expense.splitType;
        _category = details.expense.category;
        _receiptPath = details.expense.receiptPath;
        _date = details.expense.createdAt;
        _payerId = details.payments.first.user.id;
        _hasMultiplePayers = details.payments.length > 1;
        _paymentPayerIds
          ..clear()
          ..addAll(details.payments.map((item) => item.user.id));
        for (final item in details.payments) {
          _paymentAmounts
              .putIfAbsent(item.user.id, TextEditingController.new)
              .text = _rupees(
            item.payment.amountPaidPaise,
          );
        }
        _selected
          ..clear()
          ..addAll(details.shares.map((item) => item.user.id));
        for (final item in details.shares) {
          _ratios.putIfAbsent(item.user.id, TextEditingController.new).text =
              '${item.share.ratio ?? 1}';
          _percentages
                  .putIfAbsent(item.user.id, TextEditingController.new)
                  .text =
              '${item.share.ratio ?? 0}';
          _custom.putIfAbsent(item.user.id, TextEditingController.new).text =
              _rupees(item.share.amountOwedPaise);
        }
        _participantsInitialized = true;
        _loadedExisting = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Could not load expense');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
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
      } else if (_type == SplitTypeDb.percentage) {
        shares = SplitEngine.percentage(
          totalPaise: amount,
          userIds: ids,
          percentages: ids
              .map((id) => int.tryParse(_percentages[id]?.text ?? '') ?? 0)
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
      final payments = _hasMultiplePayers
          ? _paymentPayerIds
                .map(
                  (id) => ExpensePaymentDraft(
                    userId: id,
                    amountPaidPaise:
                        _paise(_paymentAmounts[id]?.text ?? '') ?? 0,
                  ),
                )
                .toList()
          : const <ExpensePaymentDraft>[];
      setState(() => _saving = true);
      final draft = ExpenseDraft(
        groupId: widget.groupId,
        title: _title.text,
        description: _description.text,
        totalAmountPaise: amount,
        payerId: _payerId!,
        payments: payments,
        participants: shares,
        splitType: _type,
        date: _date,
        category: _category,
        receiptPath: _receiptPath,
      );
      final repository = ref.read(expenseRepositoryProvider);
      if (widget.expenseId == null) {
        await repository.create(draft);
      } else {
        await repository.update(widget.expenseId!, draft);
      }
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

  Future<void> _chooseReceipt() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            if (_receiptPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove receipt'),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      setState(() => _receiptPath = null);
      return;
    }
    try {
      final image = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (image != null && mounted) setState(() => _receiptPath = image.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not select receipt image')),
        );
      }
    }
  }

  Future<void> _chooseCategory() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppConstants.expenseCategories
                    .map(
                      (category) => ChoiceChip(
                        label: Text(category),
                        selected: category == _category,
                        avatar: Icon(_categoryIcon(category), size: 18),
                        onSelected: (_) => Navigator.pop(context, category),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) setState(() => _category = chosen);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit expense')),
        body: Center(child: Text(_loadError!)),
      );
    }
    if (!_loadedExisting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
        if (!_participantsInitialized) {
          _selected.addAll(members.map((m) => m.id));
          _participantsInitialized = true;
        }
        for (final member in members) {
          _ratios.putIfAbsent(
            member.id,
            () => TextEditingController(text: '1'),
          );
          _percentages.putIfAbsent(
            member.id,
            () => TextEditingController(text: '0'),
          );
          _custom.putIfAbsent(member.id, TextEditingController.new);
          _paymentAmounts.putIfAbsent(member.id, TextEditingController.new);
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.expenseId == null ? 'Add expense' : 'Edit expense',
            ),
          ),
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹  ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) =>
                      _paise(value ?? '') == null || _paise(value ?? '')! <= 0
                      ? 'Enter a positive amount with up to 2 decimals'
                      : null,
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(_categoryIcon(_category)),
                    ),
                    title: const Text('Category'),
                    subtitle: Text(_category),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _chooseCategory,
                  ),
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Multiple people paid'),
                  subtitle: const Text('Record each person\'s contribution'),
                  value: _hasMultiplePayers,
                  onChanged: (value) => setState(() {
                    _hasMultiplePayers = value;
                    if (value && _payerId != null) {
                      _paymentPayerIds.add(_payerId!);
                    }
                  }),
                ),
                if (_hasMultiplePayers) ...[
                  ...members.map(
                    (m) => Row(
                      children: [
                        Checkbox(
                          value: _paymentPayerIds.contains(m.id),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _paymentPayerIds.add(m.id);
                            } else {
                              _paymentPayerIds.remove(m.id);
                            }
                          }),
                        ),
                        Expanded(
                          child: Text(
                            m.isCurrentUser ? '${m.name} (You)' : m.name,
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            enabled: _paymentPayerIds.contains(m.id),
                            controller: _paymentAmounts[m.id],
                            decoration: const InputDecoration(
                              labelText: 'Paid (₹)',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (value) {
                              if (!_paymentPayerIds.contains(m.id)) return null;
                              final amount = _paise(value ?? '');
                              return amount == null || amount <= 0
                                  ? 'Enter a positive amount'
                                  : null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Payer amounts must add up exactly to the expense total.',
                  ),
                  if (_paymentValidationMessage() case final message?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<SplitTypeDb>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: SplitTypeDb.equal,
                        label: Text('Equal', softWrap: false),
                      ),
                      ButtonSegment(
                        value: SplitTypeDb.specificAmount,
                        label: Text('Amount', softWrap: false),
                      ),
                      ButtonSegment(
                        value: SplitTypeDb.ratio,
                        label: Text('Ratio', softWrap: false),
                      ),
                      ButtonSegment(
                        value: SplitTypeDb.percentage,
                        label: Text('Percent', softWrap: false),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) =>
                        setState(() => _type = value.first),
                  ),
                ),
                if (_type != SplitTypeDb.equal) ...[
                  const SizedBox(height: 12),
                  ...members
                      .where((m) => _selected.contains(m.id))
                      .map(
                        (m) => TextFormField(
                          controller: _type == SplitTypeDb.ratio
                              ? _ratios[m.id]
                              : _type == SplitTypeDb.percentage
                              ? _percentages[m.id]
                              : _custom[m.id],
                          decoration: InputDecoration(
                            labelText: _type == SplitTypeDb.ratio
                                ? 'Ratio for ${m.name}'
                                : _type == SplitTypeDb.percentage
                                ? 'Percent for ${m.name}'
                                : 'Amount for ${m.name} (₹)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            if (_type == SplitTypeDb.ratio) {
                              final ratio = int.tryParse(value ?? '');
                              return ratio == null || ratio < 0
                                  ? 'Enter a non-negative whole number'
                                  : null;
                            }
                            if (_type == SplitTypeDb.percentage) {
                              final percentage = int.tryParse(value ?? '');
                              return percentage == null || percentage < 0
                                  ? 'Enter a non-negative whole number'
                                  : null;
                            }
                            final amount = _paise(value ?? '');
                            return amount == null || amount <= 0
                                ? 'Enter a positive amount'
                                : null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  if (_allocationStatus() case final status?) ...[
                    const SizedBox(height: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color:
                            status.contains('Remaining:') ||
                                status.startsWith('Add at least')
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading:
                        _receiptPath != null && File(_receiptPath!).existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_receiptPath!),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.receipt_long_outlined),
                            ),
                          )
                        : const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      _receiptPath == null
                          ? 'Add receipt (optional)'
                          : 'Receipt attached',
                    ),
                    subtitle: const Text('Stored only on this device'),
                    trailing: TextButton(
                      onPressed: _chooseReceipt,
                      child: Text(_receiptPath == null ? 'Add' : 'Change'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      _saving ||
                          _selected.isEmpty ||
                          _paymentValidationMessage() != null
                      ? null
                      : _save,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : Text(
                          widget.expenseId == null
                              ? 'Save expense'
                              : 'Save changes',
                        ),
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
