import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return userAsync.when(
      data: (user) =>
          user == null ? const OnboardingScreen() : const RootShell(),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Database error: $e')),
      ),
    );
  }
}
