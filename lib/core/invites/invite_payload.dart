import 'dart:convert';
import 'dart:math';

/// A compact invitation. Version 3 identifies the cloud invitation only; it
/// intentionally contains no profile, UPI, local database, or group data.
/// Versions 1 and 2 remain decodable only to give existing installs a clear
/// upgrade message instead of treating their codes as arbitrary QR data.
class GroupInvitePayload {
  const GroupInvitePayload._({
    required this.version,
    required this.token,
    this.groupId,
    this.groupName,
    this.memberNames = const [],
    this.invitationId,
  });

  const GroupInvitePayload.local({
    required String groupId,
    required String token,
  }) : this._(version: 1, groupId: groupId, token: token);

  const GroupInvitePayload.portable({
    required String groupName,
    required List<String> memberNames,
    required String token,
  }) : this._(
         version: 2,
         groupName: groupName,
         memberNames: memberNames,
         token: token,
       );

  const GroupInvitePayload.cloud({
    required String invitationId,
    required String token,
  }) : this._(version: 3, invitationId: invitationId, token: token);

  final int version;
  final String token;
  final String? groupId;
  final String? groupName;
  final List<String> memberNames;
  final String? invitationId;

  bool get isPortable => version == 2;
  bool get isLegacyLocal => version == 1;
  bool get isCloudInvitation => version == 3;

  static const _type = 'campus_quicksplit_group_invite';

  String encode() {
    if (isLegacyLocal) {
      return jsonEncode({
        'type': _type,
        'version': version,
        'groupId': groupId,
        'token': token,
      });
    }
    if (isCloudInvitation) {
      return jsonEncode({
        'type': _type, 'version': version,
        'invitationId': invitationId, 'token': token,
      });
    }
    return jsonEncode({
      'type': _type,
      'version': version,
      'groupName': groupName,
      'memberNames': memberNames,
      'token': token,
    });
  }

  static GroupInvitePayload decode(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['type'] != _type || value['version'] is! int) {
        throw const FormatException('Not a Campus QuickSplit invitation');
      }
      final version = value['version'] as int;
      final token = value['token'];
      if (token is! String || token.length < 16) {
        throw const FormatException();
      }
      if (version == 1) {
        final groupId = value['groupId'];
        if (groupId is! String || groupId.isEmpty) {
          throw const FormatException();
        }
        return GroupInvitePayload.local(groupId: groupId, token: token);
      }
      if (version == 2) {
        final groupName = value['groupName'];
        final rawMembers = value['memberNames'];
        if (groupName is! String ||
            groupName.trim().isEmpty ||
            rawMembers is! List) {
          throw const FormatException();
        }
        final members = rawMembers
            .map((entry) => entry is String ? entry.trim() : '')
            .toList();
        if (members.isEmpty || members.any((name) => name.isEmpty)) {
          throw const FormatException();
        }
        return GroupInvitePayload.portable(
          groupName: groupName.trim(),
          memberNames: members,
          token: token,
        );
      }
      if (version == 3) {
        final invitationId = value['invitationId'];
        if (invitationId is! String ||
            !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}$').hasMatch(invitationId)) {
          throw const FormatException();
        }
        return GroupInvitePayload.cloud(
          invitationId: invitationId,
          token: token,
        );
      }
      throw const FormatException('Unsupported invitation version');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid invitation');
    }
  }
}

String newInviteToken() {
  final random = Random.secure();
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(
    32,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
