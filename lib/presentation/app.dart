import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'providers/database_provider.dart';
import 'providers/user_providers.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/root/root_shell.dart';

class CampusQuickSplitApp extends ConsumerWidget {
  const CampusQuickSplitApp({super.key});

  ThemeMode _themeModeFrom(String stored) {
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final themeMode = settingsAsync.valueOrNull != null
        ? _themeModeFrom(settingsAsync.value!.themeMode)
        : ThemeMode.system;

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const _StartupGate(),
    );
  }
}

/// Decides between onboarding and the main app shell based on whether a
/// current user already exists in the database — not a one-time
/// "first launch" flag alone, so a corrupted/cleared user table can't
/// leave the user stuck on the dashboard with no local identity.
class _StartupGate extends ConsumerWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final settingsAsync = ref.watch(appSettingsProvider);

    return userAsync.when(
      data: (user) {
        if (user == null) {
          // A completed profile must never be sent back into onboarding while
          // a sync transaction is replacing/restoring its local user row.
          if (settingsAsync.valueOrNull?.onboardingComplete ?? false) {
            return const _ProfileRefreshScreen();
          }
          return const OnboardingScreen();
        }
        if (settingsAsync.valueOrNull?.lockEnabled ?? false) {
          return const _DeviceLockScreen();
        }
        return const RootShell();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Database error: $e'))),
    );
  }
}

class _ProfileRefreshScreen extends ConsumerStatefulWidget {
  const _ProfileRefreshScreen();

  @override
  ConsumerState<_ProfileRefreshScreen> createState() =>
      _ProfileRefreshScreenState();
}

class _ProfileRefreshScreenState extends ConsumerState<_ProfileRefreshScreen> {
  var _attempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recover());
  }

  Future<void> _recover() async {
    if (_attempted) return;
    _attempted = true;
    final account = firebase_auth.FirebaseAuth.instance.currentUser;
    if (account == null) return;
    try {
      await ref
          .read(userRepositoryProvider)
          .recoverCurrentUser(
            name:
                account.displayName ??
                account.email?.split('@').first ??
                'User',
            email: account.email,
          );
    } catch (error) {
      debugPrint('[QuickSplit profile] recovery failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Refreshing your local profile…'),
        ],
      ),
    ),
  );
}

class _DeviceLockScreen extends StatefulWidget {
  const _DeviceLockScreen();

  @override
  State<_DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends State<_DeviceLockScreen> {
  bool _unlocked = false;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_checking || _unlocked) return;
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final authenticated = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock Campus QuickSplit',
      );
      if (!mounted) return;
      setState(() {
        _unlocked = authenticated;
        _message = authenticated
            ? null
            : 'Authentication was not completed. Try again to unlock.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Device authentication is unavailable. Turn the lock off in settings after authenticating on a supported device.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return const RootShell();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: AppConstants.spaceMd),
              Text(
                'Campus QuickSplit is locked',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (_message != null) ...[
                const SizedBox(height: AppConstants.spaceSm),
                Text(_message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: AppConstants.spaceLg),
              FilledButton.icon(
                onPressed: _checking ? null : _authenticate,
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(_checking ? 'Checking…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
