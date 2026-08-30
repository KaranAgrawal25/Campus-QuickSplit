import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/invites/invite_payload.dart';
import '../../../data/repositories/invite_repository.dart';
import '../../providers/group_providers.dart';
import '../../providers/invite_providers.dart';
import '../../providers/user_providers.dart';

class ScanInviteScreen extends ConsumerStatefulWidget {
  const ScanInviteScreen({super.key});

  @override
  ConsumerState<ScanInviteScreen> createState() => _ScanInviteScreenState();
}

/// Owns one scanner controller for this route. MobileScanner's automatic app
/// lifecycle management is disabled because this state explicitly starts and
/// stops the same controller, preventing competing start/stop calls that can
/// restart the Android preview (the visible blink reported on real devices).
class _ScanInviteScreenState extends ConsumerState<ScanInviteScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  bool _started = false;
  bool _starting = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScanner());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startScanner();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopScanner();
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || _handled || _started || _starting) return;
    _starting = true;
    try {
      await _controller.start();
      if (mounted) {
        setState(() {
          _started = true;
          _cameraError = null;
        });
      }
    } on MobileScannerException catch (error) {
      if (mounted) setState(() => _cameraError = _cameraMessage(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _cameraError =
              'Could not start the camera. Check camera permission and try again.',
        );
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopScanner() async {
    if (!_started) return;
    _started = false;
    try {
      await _controller.stop();
    } catch (_) {
      // The platform may already have released the camera during a lifecycle
      // transition. The controller is still disposed by this state.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _detect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    _handled = true;
    await _stopScanner();
    try {
      final payload = GroupInvitePayload.decode(raw);
      if (payload.isCloudInvitation) {
        await _joinCloud(payload);
      } else if (payload.isPortable) {
        throw StateError(
          'This is an older offline invitation. Ask the group owner to generate a new QR code.',
        );
      } else {
        await _joinLegacyLocal(payload);
      }
    } on InviteValidationFailure catch (failure) {
      _showMessage(_message(failure));
      await _retry();
    } on FormatException catch (_) {
      _showMessage('This QR code is not a valid Campus QuickSplit invitation.');
      await _retry();
    } on StateError catch (error) {
      _showMessage(error.message.toString());
      await _retry();
    } catch (_) {
      _showMessage('Could not read this invitation. Please try again.');
      await _retry();
    }
  }

  Future<void> _joinLegacyLocal(GroupInvitePayload payload) async {
    final validated = await ref
        .read(inviteRepositoryProvider)
        .validate(payload);
    final current = await ref.read(currentUserProvider.future);
    if (current == null) throw StateError('Your profile is unavailable');
    final members = await ref
        .read(groupRepositoryProvider)
        .members(validated.group.id);
    if (members.any((user) => user.id == current.id)) {
      throw StateError('You are already a member of this group.');
    }
    final join = await _confirmJoin(
      groupName: validated.group.name,
      memberCount: members.length,
      portable: false,
    );
    if (join != true) {
      await _retry();
      return;
    }
    await ref
        .read(groupRepositoryProvider)
        .addExistingMember(validated.group.id, current.id);
    _complete('Joined group successfully');
  }

  Future<void> _joinCloud(GroupInvitePayload payload) async {
    throw StateError(
      'Secure cross-account invitations are not available in this build.',
    );
  }

  Future<bool?> _confirmJoin({
    required String groupName,
    required int memberCount,
    required bool portable,
  }) {
    if (!mounted) return Future.value(false);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join Group?'),
        content: Text(
          '$groupName${memberCount > 0 ? '\n\nMembers: $memberCount' : ''}\n\nYou will join the same shared cloud group. If you are offline, the request is queued and no local copy is created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Join Group'),
          ),
        ],
      ),
    );
  }

  Future<void> _retry() async {
    _handled = false;
    await _startScanner();
  }

  void _complete(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _message(InviteValidationFailure failure) => switch (failure) {
    InviteValidationFailure.expired => 'This invitation has expired.',
    InviteValidationFailure.inactive => 'This invitation is no longer active.',
    InviteValidationFailure.groupMissing =>
      'This group is no longer available.',
    InviteValidationFailure.invalid =>
      'This invitation is invalid on this device.',
  };

  String _cameraMessage(
    MobileScannerException error,
  ) => switch (error.errorCode) {
    MobileScannerErrorCode.permissionDenied =>
      'Camera permission was denied. Allow camera access in Android settings, then try again.',
    MobileScannerErrorCode.unsupported =>
      'This device does not support camera scanning.',
    _ => 'Could not start the camera. Please try again.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan Group QR'),
      actions: [
        IconButton(
          tooltip: 'Retry camera',
          onPressed: _starting ? null : _startScanner,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          useAppLifecycleState: false,
          onDetect: _detect,
          placeholderBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_cameraMessage(error), textAlign: TextAlign.center),
            ),
          ),
        ),
        if (_cameraError != null)
          Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_cameraError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _startScanner,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Point your camera at a Campus QuickSplit group invitation.',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
