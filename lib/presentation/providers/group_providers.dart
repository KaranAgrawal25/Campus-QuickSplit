import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/group_repository.dart';
import 'database_provider.dart';

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => GroupRepository(ref.watch(appDatabaseProvider)),
);
final groupsProvider = StreamProvider<List<Group>>(
  (ref) => ref.watch(groupRepositoryProvider).watchGroups(),
);
final archivedGroupsProvider = StreamProvider<List<Group>>(
  (ref) => ref.watch(groupRepositoryProvider).watchArchivedGroups(),
);
final groupProvider = StreamProvider.family<GroupWithMembers?, String>(
  (ref, id) => ref.watch(groupRepositoryProvider).watchGroup(id),
);
