import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../data/database/app_database.dart';
import '../../../data/repositories/firebase_auth_repository.dart';
import '../../../data/repositories/sync_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/manual_sync_provider.dart';
import '../../providers/user_providers.dart';
import '../analytics/analytics_screen.dart';
import 'recurring_expenses_screen.dart';
import 'reminders_screen.dart';
import '../../widgets/app_ui.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<ManualSyncState>(manualSyncProvider, (_, next) {
      if (next.message != null &&
          next.phase != ManualSyncPhase.running &&
          mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.message!)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final syncRun = ref.watch(manualSyncProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionHeader('PROFILE'),
          // Keep this route reactive when Firebase restores or changes a
          // session. Sync uses the same persisted session.
          ref
              .watch(cloudAuthStateProvider)
              .when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (_) => const SizedBox.shrink(),
              ),
          ref
              .watch(currentUserProvider)
              .when(
                loading: () => const ListTile(
                  title: Text('My Profile'),
                  trailing: CircularProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (user) => user == null
                    ? const SizedBox.shrink()
                    : Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            child: Text(user.initials),
                          ),
                          title: Text(user.name),
                          subtitle: Text(
                            '${user.email ?? 'Local profile'}\n${user.phoneNumber ?? 'No phone added'} · ${user.upiId ?? 'No UPI ID added'}',
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.edit_rounded),
                          onTap: () => _editProfile(context, ref, user),
                        ),
                      ),
              ),
          const _SectionHeader('SYNC & DATA'),
          ref
              .watch(syncStatusProvider)
              .when(
                loading: () => const ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('Data Sync'),
                  subtitle: Text('Checking local sync queue…'),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (status) => _SyncStatusCard(
                  status: status,
                  running: syncRun.isRunning,
                  onSync: () => ref.read(manualSyncProvider.notifier).syncNow(),
                ),
              ),
          if (ref.watch(cloudAuthRepositoryProvider) case final auth?)
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(
                  auth.isSignedIn
                      ? 'Cloud account connected'
                      : 'Sign in to cloud sync',
                ),
                subtitle: Text(
                  auth.isSignedIn
                      ? 'Your profile and groups are available across devices.'
                      : 'Use the same account on every device to restore your private data.',
                ),
                trailing: auth.isSignedIn
                    ? TextButton(
                        onPressed: auth.signOut,
                        child: const Text('Sign out'),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: auth.isSignedIn
                    ? null
                    : () => _signInToCloud(context, auth),
              ),
            ),
          const _SectionHeader('PREFERENCES'),
          AppSettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Balance reminders',
            subtitle: 'Schedule one-time or recurring reminders',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RemindersScreen()),
            ),
          ),
          AppSettingsTile(
            icon: Icons.repeat_outlined,
            title: 'Recurring expenses',
            subtitle: 'Review, pause, or create due expense instances',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RecurringExpensesScreen(),
              ),
            ),
          ),
          const _SectionHeader('APP & DATA'),
          AppSettingsTile(
            icon: Icons.insights_outlined,
            title: 'Analytics',
            subtitle: 'Review your spending by category and group',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
            ),
          ),
          AppSettingsTile(
            icon: Icons.file_download_outlined,
            title: 'Export expenses',
            subtitle: 'Save a CSV in your Campus QuickSplit folder',
            trailing: const Icon(Icons.download_outlined),
            onTap: () async {
              try {
                final file = await ref
                    .read(exportRepositoryProvider)
                    .exportExpensesCsv();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Saved to Campus QuickSplit/Exports/${file.path.split('/').last}',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not export expenses')),
                  );
                }
              }
            },
          ),
          const _SectionHeader('BACKUP & RESTORE'),
          AppSettingsTile(
            icon: Icons.backup_outlined,
            title: 'Create backup',
            subtitle: 'Save a local backup in your Campus QuickSplit folder',
            trailing: const Icon(Icons.save_alt_outlined),
            onTap: () async {
              try {
                final file = await ref
                    .read(backupRepositoryProvider)
                    .createBackup();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Saved to Campus QuickSplit/Backups/${file.path.split('/').last}',
                      ),
                    ),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not create backup')),
                  );
                }
              }
            },
          ),
          const AppSettingsTile(
            icon: Icons.restore_page_outlined,
            title: 'Restore backup',
            subtitle: 'For safety, backup restore is available during first-time setup',
            trailing: Icon(Icons.info_outline),
          ),
          const _SectionHeader('SECURITY & APPEARANCE'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock Campus QuickSplit'),
            subtitle: const Text(
              'Require your device authentication when opening the app',
            ),
            trailing: Switch(
              value:
                  ref.watch(appSettingsProvider).valueOrNull?.lockEnabled ??
                  false,
              onChanged: (enabled) async {
                await (ref
                        .read(appDatabaseProvider)
                        .update(ref.read(appDatabaseProvider).appSettingsTable)
                      ..where((settings) => settings.id.equals(0)))
                    .write(
                      AppSettingsTableCompanion(lockEnabled: Value(enabled)),
                    );
              },
            ),
          ),
          ListTile(
            title: const Text('Theme'),
            subtitle: const Text('Choose how Campus QuickSplit looks'),
            trailing: DropdownButton<String>(
              value:
                  ref.watch(appSettingsProvider).valueOrNull?.themeMode ??
                  'system',
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'light', child: Text('Light')),
                DropdownMenuItem(value: 'dark', child: Text('Dark')),
              ],
              onChanged: (value) {
                if (value != null) {
                  (ref
                          .read(appDatabaseProvider)
                          .update(
                            ref.read(appDatabaseProvider).appSettingsTable,
                          )
                        ..where((s) => s.id.equals(0)))
                      .write(
                        AppSettingsTableCompanion(themeMode: Value(value)),
                      );
                }
              },
            ),
          ),
          const _SectionHeader('ABOUT'),
          const AboutListTile(
            applicationName: 'Campus QuickSplit',
            applicationVersion: '0.1.0',
            applicationLegalese: 'Local-first student expense splitting',
          ),
        ],
      ),
    );
  }

  Future<void> _signInToCloud(
    BuildContext context,
    FirebaseAuthRepository auth,
  ) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _CloudAuthDialog(auth: auth),
    );
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final name = TextEditingController(text: user.name);
    final email = TextEditingController(text: user.email);
    final phone = TextEditingController(text: user.phoneNumber);
    final upi = TextEditingController(text: user.upiId);
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (from cloud account when connected)',
                ),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              TextField(
                controller: upi,
                decoration: const InputDecoration(
                  labelText: 'UPI ID (not verified)',
                ),
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
              child: const Text('Save Changes'),
            ),
          ],
        ),
      );
      if (save == true && context.mounted) {
        try {
          await ref
              .read(userRepositoryProvider)
              .updateProfile(
                userId: user.id,
                name: name.text,
                email: email.text,
                phoneNumber: phone.text,
                upiId: upi.text,
              );
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Profile updated')));
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please check your profile details'),
              ),
            );
          }
        }
      }
    } finally {
      name.dispose();
      email.dispose();
      phone.dispose();
      upi.dispose();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 6, left: 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.status,
    required this.running,
    required this.onSync,
  });
  final SyncStatus status;
  final bool running;
  final VoidCallback onSync;
  @override
  Widget build(BuildContext context) {
    final (icon, headline, message) = switch (status.state) {
      SyncState.synced => (
        Icons.cloud_done_outlined,
        'Everything is synced',
        'Your cloud data is up to date.',
      ),
      SyncState.pending => (
        Icons.cloud_upload_outlined,
        'Offline changes pending',
        '${status.pendingCount} change${status.pendingCount == 1 ? '' : 's'} waiting to sync.',
      ),
      SyncState.failed => (
        Icons.cloud_off_outlined,
        'Sync couldn’t complete',
        '${status.failedCount} change${status.failedCount == 1 ? '' : 's'} will retry when possible.',
      ),
      SyncState.localOnly => (
        Icons.phone_android_outlined,
        'Stored safely on this device',
        'Cloud sync is not set up. You can still use QuickSplit offline.',
      ),
    };
    return Card(
      child: ListTile(
        leading: Semantics(
          label: headline,
          child: Icon(
            icon,
            color: status.state == SyncState.failed
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(headline),
        subtitle: Text(message),
        trailing: status.state == SyncState.localOnly
            ? null
            : TextButton(
                onPressed: running ? null : onSync,
                child: running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sync now'),
              ),
      ),
    );
  }
}

class _CloudAuthDialog extends StatefulWidget {
  const _CloudAuthDialog({required this.auth});
  final FirebaseAuthRepository auth;

  @override
  State<_CloudAuthDialog> createState() => _CloudAuthDialogState();
}

class _CloudAuthDialogState extends State<_CloudAuthDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _create = false;
  var _emailCreate = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_emailCreate) {
        await widget.auth.createAccount(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await widget.auth.signIn(email: _email.text, password: _password.text);
      }
      if (mounted) {
        Navigator.pop(context, 'Cloud account connected');
      }
    } on FirebaseAuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not reach Firebase. Check your connection and configuration.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final connected = await widget.auth.signInWithGoogle();
      if (!mounted) return;
      if (connected) {
        Navigator.pop(context, 'Cloud account connected');
      } else {
        setState(() => _error = 'Google sign-in was cancelled');
      }
    } on FirebaseAuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect your cloud account'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Your profile and synced data can be available across your devices.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.g_mobiledata),
              label: const Text('Continue with Google'),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _create = !_create),
            child: Text(
              _create ? 'Use Google instead' : 'Use email and password instead',
            ),
          ),
          if (_create) ...[
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email address'),
              validator: (value) =>
                  FirebaseAuthRepository.validateEmail(value ?? ''),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _emailCreate = !_emailCreate),
              child: Text(
                _emailCreate
                    ? 'I already have an account'
                    : 'Create an account',
              ),
            ),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Password (8+ characters)',
              ),
              validator: (value) =>
                  FirebaseAuthRepository.validatePassword(value ?? ''),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_create)
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_emailCreate ? 'Create account' : 'Sign in'),
        ),
    ],
  );
}
