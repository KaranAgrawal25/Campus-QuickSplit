import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'cloud_id_repository.dart';

/// The narrow interface a configured cloud backend must implement. Keeping it
/// independent from UI and Drift lets the app remain fully usable offline and
/// avoids pretending a backend exists before credentials/auth are configured.
abstract interface class SyncTransport {
  bool get isConfigured;
  bool get isAuthenticated;

  /// Stable account identity when the transport has authenticated one. This
  /// is used before serializing the local current-user payload so every
  /// membership and expense reference uses the same cloud ID.
  String? get authenticatedUserId;

  /// Cross-account group sharing needs a server-authorized membership model.
  /// A transport must opt in explicitly; private account backup is not enough.
  bool get supportsSharedInvites;
  Future<void> push(SyncOperation operation);

  /// Returns changes after [cursor], ordered oldest first. A transport must
  /// return an identical change at most once for a cursor, but the applier is
  /// still idempotent because mobile retries and reconnects are unavoidable.
  Future<SyncPullResult> pull({String? cursor});
}

class SyncPullResult {
  const SyncPullResult({required this.changes, this.cursor});
  final List<CloudSyncChange> changes;
  final String? cursor;
}

class CloudSyncChange {
  const CloudSyncChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.payload,
  });
  final String id, entityType, entityId;
  final Map<String, Object?> payload;
}

abstract interface class SyncChangeApplier {
  Future<void> apply(List<CloudSyncChange> changes);
}

/// Manual sync must not leave the UI waiting forever when the device has a
/// captive portal, a stalled radio, or a Firebase request that never returns.
const syncNetworkTimeout = Duration(seconds: 20);

class SyncTimeoutException implements Exception {
  const SyncTimeoutException();

  @override
  String toString() => 'Sync timed out';
}

class UnconfiguredSyncTransport implements SyncTransport {
  const UnconfiguredSyncTransport();

  @override
  bool get isConfigured => false;

  @override
  bool get isAuthenticated => false;

  @override
  String? get authenticatedUserId => null;

  @override
  bool get supportsSharedInvites => false;

  @override
  Future<void> push(SyncOperation operation) =>
      throw UnsupportedError('Cloud sync is not configured');

  @override
  Future<SyncPullResult> pull({String? cursor}) =>
      throw UnsupportedError('Cloud sync is not configured');
}

enum SyncState { localOnly, synced, pending, failed }

class SyncStatus {
  const SyncStatus({
    required this.state,
    required this.pendingCount,
    required this.failedCount,
  });

  final SyncState state;
  final int pendingCount;
  final int failedCount;
}

class SyncRunResult {
  const SyncRunResult({
    required this.uploaded,
    required this.downloaded,
    required this.failed,
    required this.pullFailed,
    required this.timedOut,
    required this.permissionDenied,
    required this.isConfigured,
    required this.isAuthenticated,
  });
  final int uploaded, downloaded, failed;
  final bool pullFailed;
  final bool timedOut;
  final bool permissionDenied;
  final bool isConfigured;
  final bool isAuthenticated;
}

class SyncRepository {
  SyncRepository(
    this._db, {
    SyncTransport? transport,
    SyncChangeApplier? applier,
    Duration operationTimeout = syncNetworkTimeout,
  }) : _transport = transport ?? const UnconfiguredSyncTransport() {
    _applier = applier;
    _operationTimeout = operationTimeout;
  }

  final AppDatabase _db;
  final SyncTransport _transport;
  late final SyncChangeApplier? _applier;
  late final Duration _operationTimeout;
  Future<SyncRunResult>? _inFlightRun;

  bool get supportsSharedInvites => _transport.supportsSharedInvites;

  /// Queues an idempotent upsert. Repeated local updates to the same entity
  /// coalesce into one pending operation, while immutable financial entities
  /// retain their UUID-based identity and cannot be duplicated remotely.
  Future<void> enqueueUpsert({
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
  }) async {
    final cloudIds = CloudIdRepository(_db);
    // Firebase UID is the canonical cloud ID for the account owner. This
    // must happen *before* dependent membership/expense payloads are built;
    // doing it only in the transport leaves those payloads pointing at a
    // discarded generated UUID and restores zero balances on another device.
    final accountId = _transport.authenticatedUserId;
    if (entityType == 'user' &&
        payload['isCurrentUser'] == true &&
        accountId != null) {
      await cloudIds.link(entityType, entityId, accountId);
    }
    final cloudId = await cloudIds.forLocal(entityType, entityId);
    final cloudPayload = await _cloudPayload(
      entityType: entityType,
      cloudId: cloudId,
      payload: payload,
      cloudIds: cloudIds,
    );
    final key = 'upsert:$entityType:$cloudId';
    final encoded = jsonEncode(cloudPayload);
    final existing =
        await (_db.select(_db.syncOperations)
              ..where((operation) => operation.operationKey.equals(key)))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              operationKey: key,
              entityType: entityType,
              entityId: cloudId,
              payloadJson: encoded,
            ),
          );
      return;
    }
    await (_db.update(
      _db.syncOperations,
    )..where((operation) => operation.id.equals(existing.id))).write(
      SyncOperationsCompanion(
        payloadJson: Value(encoded),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        lastError: const Value(null),
        syncedAt: const Value(null),
      ),
    );
  }

  /// A scan is a request to join an existing cloud invitation, not a request
  /// to manufacture a local group. It is durable when offline and uses the
  /// invitation's global ID as the idempotency key.
  Future<void> enqueueInviteJoin({
    required String invitationCloudId,
    required String token,
  }) => _enqueueRaw(
    operationKey: 'join-invite:$invitationCloudId',
    entityType: 'invite_join',
    entityId: invitationCloudId,
    payload: {'invitationId': invitationCloudId, 'token': token},
  );

  Future<void> _enqueueRaw({
    required String operationKey,
    required String entityType,
    required String entityId,
    required Map<String, Object?> payload,
  }) async {
    final encoded = jsonEncode(payload);
    final existing =
        await (_db.select(_db.syncOperations)..where(
              (operation) => operation.operationKey.equals(operationKey),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              operationKey: operationKey,
              entityType: entityType,
              entityId: entityId,
              payloadJson: encoded,
            ),
          );
      return;
    }
    await (_db.update(
      _db.syncOperations,
    )..where((operation) => operation.id.equals(existing.id))).write(
      SyncOperationsCompanion(
        payloadJson: Value(encoded),
        createdAt: Value(DateTime.now()),
        retryCount: const Value(0),
        lastError: const Value(null),
        syncedAt: const Value(null),
      ),
    );
  }

  Stream<SyncStatus> watchStatus() {
    final query = _db.select(_db.syncOperations);
    return query.watch().map(_statusFrom);
  }

  SyncStatus _statusFrom(List<SyncOperation> operations) {
    final pending = operations.where((operation) => operation.syncedAt == null);
    final pendingCount = pending.length;
    final failedCount = pending
        .where((operation) => operation.lastError != null)
        .length;
    return SyncStatus(
      state: !_transport.isConfigured
          ? SyncState.localOnly
          : failedCount > 0
          ? SyncState.failed
          : pendingCount > 0
          ? SyncState.pending
          : SyncState.synced,
      pendingCount: pendingCount,
      failedCount: failedCount,
    );
  }

  /// Returns the active run when automatic sync and the Sync now button race.
  /// There must only ever be one writer consuming the durable outbox.
  Future<SyncRunResult> syncPending() {
    final active = _inFlightRun;
    if (active != null) return active;
    final run = _syncPending();
    _inFlightRun = run;
    run.then(
      (_) {
        if (identical(_inFlightRun, run)) _inFlightRun = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_inFlightRun, run)) _inFlightRun = null;
      },
    );
    return run;
  }

  Future<SyncRunResult> _syncPending() async {
    debugPrint(
      '[QuickSplit sync] start configured=${_transport.isConfigured} authenticated=${_transport.isAuthenticated}',
    );
    if (!_transport.isConfigured || !_transport.isAuthenticated) {
      return SyncRunResult(
        uploaded: 0,
        downloaded: 0,
        failed: 0,
        pullFailed: false,
        timedOut: false,
        permissionDenied: false,
        isConfigured: _transport.isConfigured,
        isAuthenticated: _transport.isAuthenticated,
      );
    }
    // Older builds could enqueue a group membership without first enqueueing
    // its member record. Before every authenticated sync, materialize a
    // complete, idempotent snapshot from the canonical local database. This
    // repairs those incomplete outboxes and ensures an uninstall/reinstall
    // can always replay stable user ids, memberships, expenses, and payments.
    try {
      await _enqueueCompleteSnapshot();
    } catch (error, stackTrace) {
      debugPrint(
        '[QuickSplit sync] local snapshot failed: $error\n$stackTrace',
      );
      return SyncRunResult(
        uploaded: 0,
        downloaded: 0,
        failed: 1,
        pullFailed: true,
        timedOut: false,
        permissionDenied: false,
        isConfigured: _transport.isConfigured,
        isAuthenticated: _transport.isAuthenticated,
      );
    }
    final pending =
        await (_db.select(_db.syncOperations)
              ..where((operation) => operation.syncedAt.isNull())
              ..orderBy([(operation) => OrderingTerm.asc(operation.createdAt)]))
            .get();
    var uploaded = 0;
    var failed = 0;
    var timedOut = false;
    var permissionDenied = false;
    for (final operation in pending) {
      try {
        await _withTimeout(_transport.push(operation));
        await (_db.update(
          _db.syncOperations,
        )..where((row) => row.id.equals(operation.id))).write(
          SyncOperationsCompanion(
            syncedAt: Value(DateTime.now()),
            lastError: const Value(null),
          ),
        );
        uploaded++;
      } catch (error) {
        debugPrint(
          '[QuickSplit sync] push failed type=${operation.entityType} id=${operation.entityId}: $error',
        );
        failed++;
        timedOut = timedOut || error is SyncTimeoutException;
        permissionDenied = permissionDenied || _isPermissionDenied(error);
        await (_db.update(
          _db.syncOperations,
        )..where((row) => row.id.equals(operation.id))).write(
          SyncOperationsCompanion(
            retryCount: Value(operation.retryCount + 1),
            lastError: Value(error.toString()),
          ),
        );
        if (error is SyncTimeoutException) break;
      }
    }
    var downloaded = 0;
    var pullFailed = false;
    if (!timedOut) {
      try {
        final pull = await _withTimeout(_transport.pull());
        if (_applier != null && pull.changes.isNotEmpty) {
          await _applier.apply(pull.changes);
          downloaded = pull.changes.length;
        }
      } on SyncTimeoutException {
        timedOut = true;
        pullFailed = true;
      } catch (error) {
        debugPrint('[QuickSplit sync] pull failed: $error');
        pullFailed = true;
        permissionDenied = permissionDenied || _isPermissionDenied(error);
        // Upload acknowledgement remains durable even if a later pull fails.
        // The next manual/automatic run retries the pull safely.
      }
    } else {
      pullFailed = true;
    }
    final result = SyncRunResult(
      uploaded: uploaded,
      downloaded: downloaded,
      failed: failed,
      pullFailed: pullFailed,
      timedOut: timedOut,
      permissionDenied: permissionDenied,
      isConfigured: true,
      isAuthenticated: _transport.isAuthenticated,
    );
    debugPrint(
      '[QuickSplit sync] end uploaded=${result.uploaded} downloaded=${result.downloaded} failed=${result.failed} pullFailed=${result.pullFailed}',
    );
    return result;
  }

  Future<void> _enqueueCompleteSnapshot() async {
    final users = await _db.select(_db.users).get();
    final current = users.where((user) => user.isCurrentUser).firstOrNull;
    final accountId = _transport.authenticatedUserId;
    if (current != null && accountId != null) {
      // Repair old installs that generated a random cloud ID for the account
      // owner before Firebase was available. Do this before scanning groups,
      // memberships, and expenses so their references are regenerated with
      // the Firebase UID in the same run.
      await CloudIdRepository(_db).link('user', current.id, accountId);
    }
    for (final user in users) {
      await enqueueUpsert(
        entityType: 'user',
        entityId: user.id,
        payload: {
          'id': user.id,
          'name': user.name,
          'initials': user.initials,
          'phoneNumber': user.phoneNumber,
          'email': user.email,
          'upiId': user.upiId,
          'isCurrentUser': user.isCurrentUser,
          'createdAt': user.createdAt.toUtc().toIso8601String(),
          'updatedAt': user.updatedAt.toUtc().toIso8601String(),
        },
      );
    }
    final groups = await _db.select(_db.groups).get();
    for (final group in groups) {
      await enqueueUpsert(
        entityType: 'group',
        entityId: group.id,
        payload: {
          'id': group.id,
          'name': group.name,
          'isArchived': group.isArchived,
          'createdAt': group.createdAt.toUtc().toIso8601String(),
        },
      );
    }
    final memberships = await _db.select(_db.groupMembers).get();
    for (final membership in memberships) {
      await enqueueUpsert(
        entityType: 'membership',
        entityId: '${membership.groupId}:${membership.userId}',
        payload: {
          'groupId': membership.groupId,
          'userId': membership.userId,
          'removed': false,
          'joinedAt': membership.joinedAt.toUtc().toIso8601String(),
        },
      );
    }
    final payments = await _db.select(_db.expensePayments).get();
    final participants = await _db.select(_db.expenseParticipants).get();
    final expenses = await _db.select(_db.expenses).get();
    for (final expense in expenses) {
      await enqueueUpsert(
        entityType: 'expense',
        entityId: expense.id,
        payload: {
          'id': expense.id,
          'groupId': expense.groupId,
          'title': expense.title,
          'description': expense.description,
          'totalAmountPaise': expense.totalAmountPaise,
          'category': expense.category,
          'splitType': expense.splitType.name,
          'createdAt': expense.createdAt.toUtc().toIso8601String(),
          'isDeleted': expense.isDeleted,
          'payments': payments
              .where((item) => item.expenseId == expense.id)
              .map(
                (item) => {
                  'userId': item.userId,
                  'amountPaidPaise': item.amountPaidPaise,
                },
              )
              .toList(),
          'participants': participants
              .where((item) => item.expenseId == expense.id)
              .map(
                (item) => {
                  'userId': item.userId,
                  'amountOwedPaise': item.amountOwedPaise,
                  'ratio': item.ratio,
                },
              )
              .toList(),
        },
      );
    }
    final templates = await _db.select(_db.recurringExpenseTemplates).get();
    for (final template in templates) {
      await enqueueUpsert(
        entityType: 'recurring_template',
        entityId: template.id,
        payload: {
          'id': template.id,
          'sourceExpenseId': template.sourceExpenseId,
          'intervalDays': template.intervalDays,
          'nextDueAt': template.nextDueAt.toUtc().toIso8601String(),
          'isActive': template.isActive,
          'createdAt': template.createdAt.toUtc().toIso8601String(),
        },
      );
    }
    final reminders = await _db.select(_db.reminderSchedules).get();
    for (final reminder in reminders) {
      await enqueueUpsert(
        entityType: 'reminder',
        entityId: reminder.id,
        payload: {
          'id': reminder.id,
          'title': reminder.title,
          'body': reminder.body,
          'frequency': reminder.frequency.name,
          'hour': reminder.hour,
          'minute': reminder.minute,
          'weekday': reminder.weekday,
          'dayOfMonth': reminder.dayOfMonth,
          'scheduledAt': reminder.scheduledAt.toUtc().toIso8601String(),
          'nextScheduledAt': reminder.nextScheduledAt.toUtc().toIso8601String(),
          'isEnabled': reminder.isEnabled,
          'createdAt': reminder.createdAt.toUtc().toIso8601String(),
          'updatedAt': reminder.updatedAt.toUtc().toIso8601String(),
        },
      );
    }
    final settlements = await _db.select(_db.settlements).get();
    for (final settlement in settlements) {
      await enqueueUpsert(
        entityType: 'settlement',
        entityId: settlement.id,
        payload: {
          'id': settlement.id,
          'groupId': settlement.groupId,
          'fromUserId': settlement.fromUserId,
          'toUserId': settlement.toUserId,
          'amountPaise': settlement.amountPaise,
          'note': settlement.note,
          'status': settlement.status.name,
          'createdAt': settlement.createdAt.toUtc().toIso8601String(),
        },
      );
    }
  }

  Future<T> _withTimeout<T>(Future<T> future) => future.timeout(
    _operationTimeout,
    onTimeout: () => throw const SyncTimeoutException(),
  );

  bool _isPermissionDenied(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('permission-denied') ||
        message.contains('permission_denied') ||
        message.contains('insufficient permissions');
  }

  Future<Map<String, Object?>> _cloudPayload({
    required String entityType,
    required String cloudId,
    required Map<String, Object?> payload,
    required CloudIdRepository cloudIds,
  }) async {
    final converted = <String, Object?>{...payload, 'id': cloudId};
    Future<String?> reference(String? type, Object? local) async {
      if (type == null || local is! String) return local as String?;
      return cloudIds.forLocal(type, local);
    }

    converted['groupId'] = await reference('group', payload['groupId']);
    converted['userId'] = await reference('user', payload['userId']);
    converted['fromUserId'] = await reference('user', payload['fromUserId']);
    converted['toUserId'] = await reference('user', payload['toUserId']);
    converted['sourceExpenseId'] = await reference(
      'expense',
      payload['sourceExpenseId'],
    );
    if (payload['payments'] is List) {
      converted['payments'] = await Future.wait(
        (payload['payments'] as List).whereType<Map>().map((payment) async {
          final item = Map<String, Object?>.from(payment);
          item['userId'] = await reference('user', item['userId']);
          return item;
        }),
      );
    }
    if (payload['participants'] is List) {
      converted['participants'] = await Future.wait(
        (payload['participants'] as List).whereType<Map>().map((
          participant,
        ) async {
          final item = Map<String, Object?>.from(participant);
          item['userId'] = await reference('user', item['userId']);
          return item;
        }),
      );
    }
    return converted;
  }
}
