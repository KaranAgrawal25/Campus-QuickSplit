import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sync_repository.dart';
import 'database_provider.dart';

enum ManualSyncPhase { idle, running, success, error }

class ManualSyncState {
  const ManualSyncState({this.phase = ManualSyncPhase.idle, this.message});
  final ManualSyncPhase phase;
  final String? message;

  bool get isRunning => phase == ManualSyncPhase.running;
}

/// Serializes user-triggered sync runs. Outbox rows are marked only after the
/// transport acknowledges them, so every error leaves local data retryable.
class ManualSyncController extends StateNotifier<ManualSyncState> {
  ManualSyncController(SyncRepository sync)
    : _runSync = sync.syncPending,
      super(const ManualSyncState());

  /// Kept public for focused UI-state tests without a real database or network.
  ManualSyncController.forTesting(Future<SyncRunResult> Function() runSync)
    : _runSync = runSync,
      super(const ManualSyncState());

  final Future<SyncRunResult> Function() _runSync;

  Future<void> syncNow() async {
    if (state.isRunning) return;
    state = const ManualSyncState(phase: ManualSyncPhase.running);
    try {
      final result = await _runSync();
      if (!result.isConfigured) {
        state = const ManualSyncState(
          phase: ManualSyncPhase.error,
          message:
              'Firebase is not configured. Your changes are safely stored on this device.',
        );
      } else if (!result.isAuthenticated) {
        state = const ManualSyncState(
          phase: ManualSyncPhase.error,
          message: 'Your cloud session has expired. Sign in again to sync.',
        );
      } else if (result.timedOut) {
        state = const ManualSyncState(
          phase: ManualSyncPhase.error,
          message:
              "Sync timed out. Your local changes are safe and will sync when you're back online.",
        );
      } else if (result.permissionDenied) {
        state = const ManualSyncState(
          phase: ManualSyncPhase.error,
          message:
              'Firestore denied access to your cloud data. Confirm you are signed in and update the Firestore rules. Your local changes are safe.',
        );
      } else if (result.failed > 0 || result.pullFailed) {
        state = ManualSyncState(
          phase: ManualSyncPhase.error,
          message: result.failed > 0
              ? 'Could not sync ${result.failed} local change${result.failed == 1 ? '' : 's'}. They remain queued.'
              : 'Could not refresh cloud changes. Your local data is unchanged.',
        );
      } else {
        state = ManualSyncState(
          phase: ManualSyncPhase.success,
          message: result.uploaded == 0 && result.downloaded == 0
              ? 'Already synced'
              : 'Synced ${result.uploaded} upload${result.uploaded == 1 ? '' : 's'} and ${result.downloaded} download${result.downloaded == 1 ? '' : 's'}',
        );
      }
    } catch (_) {
      state = const ManualSyncState(
        phase: ManualSyncPhase.error,
        message:
            'Could not start sync. Check your connection and try again. Your local changes are safe.',
      );
    } finally {
      // A future implementation must never strand the action in loading.
      if (state.isRunning) {
        state = const ManualSyncState(
          phase: ManualSyncPhase.error,
          message: 'Sync stopped unexpectedly. Your local changes are safe.',
        );
      }
    }
  }
}

final manualSyncProvider =
    StateNotifierProvider<ManualSyncController, ManualSyncState>((ref) {
      return ManualSyncController(ref.watch(syncRepositoryProvider));
    });
