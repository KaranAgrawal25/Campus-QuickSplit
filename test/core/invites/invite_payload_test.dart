import 'package:campus_quicksplit/core/invites/invite_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cloud payload round trips without local or profile data', () {
    const payload = GroupInvitePayload.cloud(
      invitationId: '51dbf891-8068-4a20-9beb-c7cbb1ff3e8f',
      token: '1234567890123456',
    );
    final decoded = GroupInvitePayload.decode(payload.encode());
    expect(decoded.isCloudInvitation, isTrue);
    expect(decoded.groupId, isNull);
    expect(decoded.groupName, isNull);
    expect(decoded.memberNames, isEmpty);
    expect(decoded.invitationId, '51dbf891-8068-4a20-9beb-c7cbb1ff3e8f');
    expect(decoded.token, '1234567890123456');
  });
  test('legacy local payload stays decodable for existing invitations', () {
    const payload = GroupInvitePayload.local(
      groupId: 'group-id',
      token: '1234567890123456',
    );
    expect(GroupInvitePayload.decode(payload.encode()).groupId, 'group-id');
  });
  test(
    'malformed payload is rejected',
    () => expect(() => GroupInvitePayload.decode('{}'), throwsFormatException),
  );
  test('cloud payload rejects malformed identifiers and short tokens', () {
    expect(
      () => GroupInvitePayload.decode(
        '{"type":"campus_quicksplit_group_invite","version":3,"invitationId":"not-a-uuid","token":"1234567890123456"}',
      ),
      throwsFormatException,
    );
    expect(
      () => GroupInvitePayload.decode(
        '{"type":"campus_quicksplit_group_invite","version":2,"groupName":"Trip","memberNames":["Karan"],"token":"short"}',
      ),
      throwsFormatException,
    );
  });
  test(
    'tokens are random',
    () => expect(newInviteToken(), isNot(newInviteToken())),
  );
}
