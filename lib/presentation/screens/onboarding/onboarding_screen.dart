import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/database/app_database.dart';
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              Icon(
                Icons.splitscreen_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),

              const SizedBox(height: AppConstants.spaceMd),

              Text(AppConstants.appName, style: theme.textTheme.headlineMedium),

              const SizedBox(height: AppConstants.spaceSm),

              Text(
                AppConstants.tagline,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: AppConstants.spaceXl),

              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'What should we call you?',
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';

                    if (trimmed.isEmpty) {
                      return 'Please enter your name';
                    }

                    if (trimmed.length > 60) {
                      return 'Name is too long';
                    }

                    return null;
                  },
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Get started'),
                ),
              ),

              const SizedBox(height: AppConstants.spaceMd),
            ],
          ),
        ),
      ),
    );
  }
}
