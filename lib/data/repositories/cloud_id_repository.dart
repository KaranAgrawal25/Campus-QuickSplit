import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Keeps local database keys private while giving every synced entity a stable
/// cloud identity. UUIDs are generated once and persisted in this mapping.
class CloudIdRepository {
  CloudIdRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<String> forLocal(String entityType, String localId) async {
    final existing = await localFor(entityType, localId);
    if (existing != null) return existing;
    final cloudId = _uuid.v4();
    await link(entityType, localId, cloudId);
    return (await localFor(entityType, localId))!;
  }

  Future<String?> localFor(String entityType, String localId) async {
    final row = await _db
        .customSelect(
          'SELECT cloud_id FROM cloud_id_mappings WHERE entity_type = ? AND local_id = ?',
          variables: [Variable<String>(entityType), Variable<String>(localId)],
        )
        .getSingleOrNull();
    return row?.read<String>('cloud_id');
  }

  Future<String?> localForCloud(String entityType, String cloudId) async {
    final row = await _db
        .customSelect(
          'SELECT local_id FROM cloud_id_mappings WHERE entity_type = ? AND cloud_id = ?',
          variables: [Variable<String>(entityType), Variable<String>(cloudId)],
        )
        .getSingleOrNull();
    return row?.read<String>('local_id');
  }

  Future<void> link(
    String entityType,
    String localId,
    String cloudId,
  ) => _db.customStatement(
    'INSERT OR REPLACE INTO cloud_id_mappings(entity_type, local_id, cloud_id) VALUES (?, ?, ?)',
    [entityType, localId, cloudId],
  );
}
