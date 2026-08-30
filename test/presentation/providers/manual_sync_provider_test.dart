import 'dart:async';

import 'package:campus_quicksplit/data/repositories/sync_repository.dart';
import 'package:campus_quicksplit/presentation/providers/manual_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SyncRunResult result({
    int uploaded = 0,
    int downloaded = 0,
    int failed = 0,
    bool pullFailed = false,
    bool timedOut = false,
    bool permissionDenied = false,
    bool isConfigured = true,
    bool isAuthenticated = true,
  }) => SyncRunResult(
    uploaded: uploaded,
    downloaded: downloaded,
    failed: failed,
    pullFailed: pullFailed,
    timedOut: timedOut,
    permissionDenied: permissionDenied,
    isConfigured: isConfigured,
    isAuthenticated: isAuthenticated,
  );

  test('manual sync reports success after flushing pending changes', () async {
    final controller = ManualSyncController.forTesting(
      () async => result(uploaded: 1, downloaded: 2),
    );
    addTearDown(controller.dispose);

    await controller.syncNow();

    expect(controller.state.phase, ManualSyncPhase.success);
    expect(controller.state.message, 'Synced 1 upload and 2 downloads');
  });

  test(
    'already synchronized manual sync still reports useful completion',
    () async {
      final controller = ManualSyncController.forTesting(() async => result());
      addTearDown(controller.dispose);

      await controller.syncNow();

      expect(controller.state.phase, ManualSyncPhase.success);
      expect(controller.state.message, 'Already synced');
    },
  );

  test('manual sync prevents simultaneous requests', () async {
    final completer = Completer<SyncRunResult>();
    var calls = 0;
    final controller = ManualSyncController.forTesting(() {
      calls++;
      return completer.future;
    });
    addTearDown(controller.dispose);

    final first = controller.syncNow();
    final second = controller.syncNow();
    expect(controller.state.phase, ManualSyncPhase.running);
    expect(calls, 1);

    completer.complete(result(uploaded: 1));
    await Future.wait([first, second]);
    expect(calls, 1);
  });

  test('manual sync keeps queued changes when transport fails', () async {
    final controller = ManualSyncController.forTesting(
      () async => result(failed: 1),
    );
    addTearDown(controller.dispose);

    await controller.syncNow();

    expect(controller.state.phase, ManualSyncPhase.error);
    expect(controller.state.message, contains('remain queued'));
    expect(controller.state.isRunning, isFalse);
  });

  test('an unexpected sync failure always clears the loading state', () async {
    final controller = ManualSyncController.forTesting(
      () => Future<SyncRunResult>.error(StateError('network failure')),
    );
    addTearDown(controller.dispose);

    await controller.syncNow();

    expect(controller.state.phase, ManualSyncPhase.error);
    expect(controller.state.isRunning, isFalse);
  });

  test('manual sync stops loading and reports a timeout', () async {
    final controller = ManualSyncController.forTesting(
      () async => result(timedOut: true, pullFailed: true),
    );
    addTearDown(controller.dispose);

    await controller.syncNow();

    expect(controller.state.phase, ManualSyncPhase.error);
    expect(controller.state.message, contains('Sync timed out'));
    expect(controller.state.isRunning, isFalse);
  });

  test('manual sync surfaces Firestore permission denial', () async {
    final controller = ManualSyncController.forTesting(
      () async => result(failed: 1, permissionDenied: true),
    );
    addTearDown(controller.dispose);

    await controller.syncNow();

    expect(controller.state.phase, ManualSyncPhase.error);
    expect(controller.state.message, contains('Firestore denied access'));
    expect(controller.state.isRunning, isFalse);
  });

  test(
    'manual sync asks for sign-in when the cloud session is absent',
    () async {
      final controller = ManualSyncController.forTesting(
        () async => result(isAuthenticated: false),
      );
      addTearDown(controller.dispose);

      await controller.syncNow();

      expect(controller.state.phase, ManualSyncPhase.error);
      expect(controller.state.message, contains('Sign in again'));
    },
  );
}
