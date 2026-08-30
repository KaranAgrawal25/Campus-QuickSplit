import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/user_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/user_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isSubmitting = false;
  int _step = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (UserRepository.validateDisplayName(_nameController.text) != null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final userRepo = ref.read(userRepositoryProvider);

      await userRepo.createCurrentUser(_nameController.text);

      final db = ref.read(appDatabaseProvider);

      await (db.update(
        db.appSettingsTable,
      )..where((s) => s.id.equals(0))).write(
        const AppSettingsTableCompanion(onboardingComplete: Value(true)),
      );

      // Navigation happens automatically:
      // main.dart watches currentUserProvider and swaps
      // to the dashboard once the user becomes non-null.
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your profile. Try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _restoreBackup() async {
    if (_isSubmitting) return;
    try {
      const type = XTypeGroup(
        label: 'Campus QuickSplit backup',
        extensions: ['json'],
        mimeTypes: ['application/json'],
      );
      final selected = await openFile(acceptedTypeGroups: [type]);
      if (selected == null || !mounted) return;
      final repository = ref.read(backupRepositoryProvider);
      final preview = await repository.inspectBackup(File(selected.path));
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore backup?'),
          content: Text(
            'This backup contains ${preview.userCount} people, ${preview.groupCount} groups, and ${preview.expenseCount} expenses. It can only be restored into this empty app and will not include receipt photos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _isSubmitting = true);
      await repository.restoreIntoEmptyDatabase(preview);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not restore that backup safely.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _step == 0
                ? _WelcomeStep(
                    key: const ValueKey('welcome'),
                    busy: _isSubmitting,
                    onContinue: () => setState(() => _step = 1),
                    onRestore: _restoreBackup,
                  )
                : _step == 1
                ? _NameStep(
                    key: const ValueKey('name'),
                    formKey: _formKey,
                    controller: _nameController,
                    onContinue: () {
                      if (_formKey.currentState?.validate() ?? false) {
                        setState(() => _step = 2);
                      }
                    },
                    onBack: () => setState(() => _step = 0),
                  )
                : _ReadyStep(
                    key: const ValueKey('ready'),
                    busy: _isSubmitting,
                    onStart: _submit,
                    onBack: () => setState(() => _step = 1),
                  ),
          ),
        ),
      ),
    );
  }
}

class _BrandSymbol extends StatelessWidget {
  const _BrandSymbol();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(24),
    ),
    child: const SizedBox(
      width: 72,
      height: 72,
      child: Icon(Icons.call_split_rounded, size: 40, color: Colors.white),
    ),
  );
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    super.key,
    required this.busy,
    required this.onContinue,
    required this.onRestore,
  });
  final bool busy;
  final VoidCallback onContinue;
  final VoidCallback onRestore;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      const _BrandSymbol(),
      const SizedBox(height: 24),
      Text(
        AppConstants.appName,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        AppConstants.tagline,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const Spacer(),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onContinue,
          child: const Text('Get started'),
        ),
      ),
      Center(
        child: TextButton.icon(
          onPressed: busy ? null : onRestore,
          icon: const Icon(Icons.restore_outlined),
          label: const Text('Restore a backup instead'),
        ),
      ),
    ],
  );
}

class _NameStep extends StatelessWidget {
  const _NameStep({
    super.key,
    required this.formKey,
    required this.controller,
    required this.onContinue,
    required this.onBack,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
      ),
      const Spacer(),
      Text(
        'What should we call you?',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'This name will appear in your groups.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => onContinue(),
          decoration: const InputDecoration(labelText: 'Name'),
          validator: UserRepository.validateDisplayName,
        ),
      ),
      const Spacer(),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onContinue,
          child: const Text('Continue'),
        ),
      ),
    ],
  );
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({
    super.key,
    required this.busy,
    required this.onStart,
    required this.onBack,
  });
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
      ),
      const Spacer(),
      const _BrandSymbol(),
      const SizedBox(height: 24),
      Text('You’re ready.', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      Text(
        'Create a group, add an expense, and QuickSplit handles the math. Your data stays available even when you’re offline.',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const Spacer(),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: busy ? null : onStart,
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Start splitting'),
        ),
      ),
    ],
  );
}
