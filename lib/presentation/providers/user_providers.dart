import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/repositories/user_repository.dart';
import 'database_provider.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(appDatabaseProvider));
});

/// Null while onboarding hasn't happened yet; the device's User record
/// once it has. Used at app startup to decide onboarding vs dashboard,
/// and by any screen that needs to know "who am I".
final currentUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(userRepositoryProvider).watchCurrentUser();
});
