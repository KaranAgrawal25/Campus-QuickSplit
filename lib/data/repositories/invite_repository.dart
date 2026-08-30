import 'package:drift/drift.dart';

import '../../core/invites/invite_payload.dart';
import '../database/app_database.dart';
import 'cloud_id_repository.dart';
import 'sync_repository.dart';

enum InviteValidationFailure { invalid, expired, inactive, groupMissing }

class ValidatedInvite {
  const ValidatedInvite(this.invite, this.group);
  final Invite invite;
  final Group group;
}

class InviteRepository {
  InviteRepository(this._db);
  final AppDatabase _db;

  Future<Invite> create(String groupId, {DateTime? expiresAt}) async {
    final group = await (_db.select(
      _db.groups,
    )..where((g) => g.id.equals(groupId))).getSingleOrNull();
    if (group == null) throw StateError('Group not found');
    final invite = await _db
        .into(_db.invites)
        .insertReturning(
          InvitesCompanion.insert(
            groupId: groupId,
            token: newInviteToken(),
            expiresAt: Value(expiresAt),
          ),
        );
    final cloudId = await CloudIdRepository(_db).forLocal('invite', invite.id);
    await SyncRepository(_db).enqueueUpsert(
      entityType: 'invite',
      entityId: invite.id,
      payload: {
        'id': cloudId,
        'groupId': invite.groupId,
        'token': invite.token,
        'isActive': invite.isActive,
        'createdAt': invite.createdAt.toUtc().toIso8601String(),
        'expiresAt': invite.expiresAt?.toUtc().toIso8601String(),
      },
    );
    return invite;
  }

  Future<Invite?> byToken(String token) => (_db.select(
    _db.invites,
  )..where((i) => i.token.equals(token))).getSingleOrNull();

  Future<ValidatedInvite> validate(GroupInvitePayload payload) async {
    if (!payload.isLegacyLocal || payload.groupId == null) {
      throw InviteValidationFailure.invalid;
    }
    final invite =
        await (_db.select(_db.invites)..where(
              (i) =>
                  i.groupId.equals(payload.groupId!) &
                  i.token.equals(payload.token),
            ))
            .getSingleOrNull();
    if (invite == null) throw InviteValidationFailure.invalid;
    if (!invite.isActive) throw InviteValidationFailure.inactive;
    if (invite.expiresAt?.isBefore(DateTime.now()) ?? false) {
      throw InviteValidationFailure.expired;
    }
    final group =
        await (_db.select(_db.groups)..where(
              (g) => g.id.equals(invite.groupId) & g.isArchived.equals(false),
            ))
            .getSingleOrNull();
    if (group == null) throw InviteValidationFailure.groupMissing;
    return ValidatedInvite(invite, group);
  }

  Future<void> revoke(String inviteId) =>
      (_db.update(_db.invites)..where((i) => i.id.equals(inviteId))).write(
        const InvitesCompanion(isActive: Value(false)),
      ).then((_) async {
        final invite = await (_db.select(_db.invites)..where((i) => i.id.equals(inviteId))).getSingle();
        await SyncRepository(_db).enqueueUpsert(
          entityType: 'invite', entityId: invite.id,
          payload: {'id': invite.id, 'groupId': invite.groupId, 'token': invite.token, 'isActive': false},
        );
      });
}
