import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/invite_repository.dart';
import 'database_provider.dart';

final inviteRepositoryProvider = Provider<InviteRepository>(
  (ref) => InviteRepository(ref.watch(appDatabaseProvider)),
);
