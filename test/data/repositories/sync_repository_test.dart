import 'dart:async';

import 'package:campus_quicksplit/data/database/app_database.dart';
import 'package:campus_quicksplit/data/repositories/sync_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'manual sync flushes an outbox row and performs a remote pull',
    () async {
      final transport = _Transport();
      final sync = SyncRepository(db, transport: transport);
      await sync.enqueueUpsert(
        entityType: 'group',
        entityId: 'local-group',
        payload: {'name': 'Trip'},
      );

      final result = await sync.syncPending();

      expect(result.uploaded, 1);
      expect(result.downloaded, 0);
      expect(transport.pushes, 1);
      expect(transport.pulls, 1);
      expect(
        (await db.select(db.syncOperations).getSingle()).syncedAt,
        isNotNull,
      );
    },
  );

  test('already-synced manual refresh still pulls remote data', () async {
    final transport = _Transport();
    final result = await SyncRepository(db, transport: transport).syncPending();

    expect(result.uploaded, 0);
    expect(transport.pulls, 1);
  });

  test(
    'failed push keeps the local outbox row pending and retryable',
    () async {
      final transport = _Transport(failPush: true);
      final sync = SyncRepository(db, transport: transport);
      await sync.enqueueUpsert(
        entityType: 'group',
        entityId: 'local-group',
        payload: {'name': 'Trip'},
      );

      final result = await sync.syncPending();
      final operation = await db.select(db.syncOperations).getSingle();

      expect(result.failed, 1);
      expect(operation.syncedAt, isNull);
      expect(operation.lastError, isNotNull);
    },
  );

  test('unconfigured transport preserves outbox rows', () async {
    final sync = SyncRepository(db);
    await sync.enqueueUpsert(
      entityType: 'group',
      entityId: 'local-group',
      payload: {'name': 'Trip'},
    );

    final result = await sync.syncPending();

    expect(result.isConfigured, isFalse);
    expect((await db.select(db.syncOperations).getSingle()).syncedAt, isNull);
  });

  test('a timed-out push leaves the outbox row unsynced', () async {
    final transport = _Transport(hangPush: true);
    final sync = SyncRepository(
      db,
      transport: transport,
      operationTimeout: const Duration(milliseconds: 10),
    );
    await sync.enqueueUpsert(
      entityType: 'group',
      entityId: 'local-group',
      payload: {'name': 'Trip'},
    );

    final result = await sync.syncPending();
    final operation = await db.select(db.syncOperations).getSingle();

    expect(result.timedOut, isTrue);
    expect(operation.syncedAt, isNull);
    expect(operation.lastError, contains('Sync timed out'));
    expect(transport.pulls, 0);
  });

  test('permission denied keeps local work pending and is reported', () async {
    final transport = _Transport(permissionDenied: true);
    final sync = SyncRepository(db, transport: transport);
    await sync.enqueueUpsert(
      entityType: 'group',
      entityId: 'local-group',
      payload: {'name': 'Trip'},
    );

    final result = await sync.syncPending();

    expect(result.permissionDenied, isTrue);
    expect(result.isAuthenticated, isTrue);
    expect((await db.select(db.syncOperations).getSingle()).syncedAt, isNull);
  });

  test('concurrent sync requests share one in-flight run', () async {
    final transport = _Transport(hangPull: true);
    final sync = SyncRepository(db, transport: transport);

    final first = sync.syncPending();
    final second = sync.syncPending();

    expect(identical(first, second), isTrue);
    transport.completePull();
    await Future.wait([first, second]);
    expect(transport.pulls, 1);
  });
}

class _Transport implements SyncTransport {
  _Transport({
    this.failPush = false,
    this.hangPush = false,
    this.hangPull = false,
    this.permissionDenied = false,
  });
  final bool failPush;
  final bool hangPush;
  final bool hangPull;
  final bool permissionDenied;
  int pushes = 0;
  int pulls = 0;
  final Completer<SyncPullResult> _pullCompleter = Completer<SyncPullResult>();
  @override
  bool get isConfigured => true;
  @override
  bool get isAuthenticated => true;
  @override
  String? get authenticatedUserId => null;
  @override
  bool get supportsSharedInvites => false;
  @override
  Future<void> push(SyncOperation operation) async {
    pushes++;
    if (hangPush) return Completer<void>().future;
    if (permissionDenied) throw StateError('PERMISSION_DENIED');
    if (failPush) throw StateError('offline');
  }

  @override
  Future<SyncPullResult> pull({String? cursor}) async {
    pulls++;
    if (hangPull) return _pullCompleter.future;
    return const SyncPullResult(changes: []);
  }

  void completePull() {
    if (!_pullCompleter.isCompleted) {
      _pullCompleter.complete(const SyncPullResult(changes: []));
    }
  }
}
