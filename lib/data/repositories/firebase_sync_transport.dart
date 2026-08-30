import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'cloud_id_repository.dart';
import 'firebase_auth_repository.dart';
import 'sync_repository.dart';

/// Firebase/Firestore transport for the durable local outbox.
///
/// Operations are keyed by their idempotency key in the authenticated user's
/// private document namespace. This gives a second device signed into the same
/// Firebase account deterministic, offline-capable reconciliation without
/// exposing financial records through client-side collection scans. The
/// Firestore document is an operation log, not the source of truth: Drift is.
class FirebaseSyncTransport implements SyncTransport {
  FirebaseSyncTransport(this._auth, this._firestore, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AppDatabase _db;

  @override
  bool get isConfigured => true;

  @override
  bool get isAuthenticated => _auth.currentUser != null;

  @override
  String? get authenticatedUserId => _auth.currentUser?.uid;

  /// Firestore is currently intentionally scoped to the signed-in account.
  /// Do not claim secure cross-account group sharing before membership rules
  /// and a reviewed server-side join flow have been deployed.
  @override
  bool get supportsSharedInvites => false;

  CollectionReference<Map<String, dynamic>> get _operations {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FirebaseAuthFailure('Sign in to sync data');
    }
    return _firestore
        .collection('quicksplitUsers')
        .doc(user.uid)
        .collection('operations');
  }

  @override
  Future<void> push(SyncOperation operation) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const FirebaseAuthFailure('Sign in to sync data');
    }
    debugPrint(
      '[QuickSplit sync] push uid=${user.uid} type=${operation.entityType} id=${operation.entityId}',
    );
    var entityId = operation.entityId;
    final payload = Map<String, Object?>.from(
      jsonDecode(operation.payloadJson) as Map,
    );
    if (operation.entityType == 'user') {
      final local = await (_db.select(
        _db.users,
      )..where((row) => row.isCurrentUser.equals(true))).getSingleOrNull();
      if (local != null) {
        entityId = user.uid;
        await CloudIdRepository(_db).link('user', local.id, entityId);
        if (user.email != null && local.email != user.email) {
          await (_db.update(_db.users)..where((row) => row.id.equals(local.id)))
              .write(UsersCompanion(email: Value(user.email)));
        }
        payload['id'] = entityId;
        payload['email'] = user.email ?? payload['email'];
      }
    }
    await _operations.doc(_documentId(operation.operationKey)).set({
      'operationKey': operation.operationKey,
      'entityType': operation.entityType,
      'entityId': entityId,
      'payload': payload,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final groupId = payload['groupId'];
    if (operation.entityType == 'group') {
      await _firestore.collection('groups').doc(entityId).set({
        'name': payload['name'],
        'archived': payload['isArchived'] == true,
        'ownerId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _firestore
          .collection('groups')
          .doc(entityId)
          .collection('members')
          .doc(user.uid)
          .set({
            'userId': user.uid,
            'displayName': user.displayName,
            'email': user.email,
            'joinedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
    if (operation.entityType == 'membership' && groupId is String) {
      final memberCloudId = payload['userId'];
      if (memberCloudId is String) {
        final profile = await _profileForCloudUser(memberCloudId);
        await _firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(memberCloudId)
            .set({
              'userId': memberCloudId,
              'displayName': profile?['name'] ?? 'Member',
              'initials': profile?['initials'] ?? '?',
              'email': profile?['email'],
              'phoneNumber': profile?['phoneNumber'],
              'upiId': profile?['upiId'],
              'joinedAt': payload['joinedAt'] ?? FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    }
    if (groupId is String && operation.entityType == 'expense') {
      final users = await _usersReferencedBy(payload);
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .doc(entityId)
          .set({
            'payload': payload,
            'users': users,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
    if (groupId is String && operation.entityType == 'settlement') {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('settlements')
          .doc(entityId)
          .set({
            'payload': payload,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
    // A write Future can finish after Firestore has accepted a local cached
    // mutation. Do not let SyncRepository clear the outbox row until the
    // server acknowledges all writes created for this operation.
    await _firestore.waitForPendingWrites();
  }

  @override
  Future<SyncPullResult> pull({String? cursor}) async {
    if (!isAuthenticated) {
      throw const FirebaseAuthFailure('Sign in to sync data');
    }
    const server = GetOptions(source: Source.server);
    final snapshot = await _operations.orderBy('updatedAt').get(server);
    debugPrint(
      '[QuickSplit sync] pull uid=${_auth.currentUser?.uid} operations=${snapshot.docs.length}',
    );
    final changes = <CloudSyncChange>[];
    String? latest;
    for (final document in snapshot.docs) {
      final data = document.data();
      final updatedAt = data['updatedAt'];
      final stamp = updatedAt is Timestamp
          ? updatedAt.toDate().toUtc().toIso8601String()
          : null;
      if (stamp != null) latest = stamp;
      // SyncRepository currently replays the private operation log. The
      // SQLite applier is idempotent, so this is safe. A future cross-account
      // group backend must supply a persisted cursor and server revision; do
      // not claim last-write-wins conflict resolution before that exists.
      final payload = data['payload'];
      if (payload is! Map ||
          data['entityType'] is! String ||
          data['entityId'] is! String) {
        continue;
      }
      changes.add(
        CloudSyncChange(
          id: document.id,
          entityType: data['entityType'] as String,
          entityId: data['entityId'] as String,
          payload: Map<String, Object?>.from(payload),
        ),
      );
    }
    // The operation log is the normal replay source. Older app versions did
    // not reliably enqueue every manual member profile, though, while they did
    // persist group mirrors and expense participant metadata. Supplement the
    // log with those mirrors so a reinstall never restores an expense without
    // the people it references (which otherwise produces ₹0 balances).
    await _appendGroupMirrorChanges(changes, server);
    // Operation documents do not have an owner field: their private parent
    // path encodes ownership. Pull only this signed-in user's direct
    // subcollection. A collection-group document-ID filter would require a
    // full document path and must never receive a bare Firebase UID.
    return SyncPullResult(changes: changes, cursor: latest);
  }

  Future<void> _appendGroupMirrorChanges(
    List<CloudSyncChange> changes,
    GetOptions server,
  ) async {
    final account = _auth.currentUser;
    if (account == null) return;
    try {
      final groups = await _firestore
          .collection('groups')
          .where('ownerId', isEqualTo: account.uid)
          .get(server);
      for (final groupDoc in groups.docs) {
        final group = groupDoc.data();
        final groupId = groupDoc.id;
        changes.add(
          CloudSyncChange(
            id: 'mirror-group-$groupId',
            entityType: 'group',
            entityId: groupId,
            payload: {
              'name': group['name'] as String? ?? 'Untitled group',
              'isArchived': group['archived'] == true,
              'createdAt': _stamp(group['updatedAt']),
            },
          ),
        );
        final knownMembers = <String>{};
        final members = await groupDoc.reference
            .collection('members')
            .get(server);
        for (final memberDoc in members.docs) {
          final member = memberDoc.data();
          final memberId = member['userId'] as String? ?? memberDoc.id;
          knownMembers.add(memberId);
          _appendMirrorUserAndMembership(
            changes,
            groupId: groupId,
            memberId: memberId,
            profile: member,
            currentAccountId: account.uid,
          );
        }
        final expenses = await groupDoc.reference
            .collection('expenses')
            .get(server);
        for (final expenseDoc in expenses.docs) {
          final expense = expenseDoc.data();
          final payload = expense['payload'];
          if (payload is! Map) continue;
          final values = Map<String, Object?>.from(payload);
          final profiles = expense['users'];
          if (profiles is Map) {
            for (final entry in profiles.entries) {
              if (entry.key is! String || entry.value is! Map) continue;
              final memberId = entry.key as String;
              if (knownMembers.add(memberId)) {
                _appendMirrorUserAndMembership(
                  changes,
                  groupId: groupId,
                  memberId: memberId,
                  profile: Map<String, Object?>.from(entry.value as Map),
                  currentAccountId: account.uid,
                );
              }
            }
          }
          changes.add(
            CloudSyncChange(
              id: 'mirror-expense-${expenseDoc.id}',
              entityType: 'expense',
              entityId: expenseDoc.id,
              payload: values,
            ),
          );
        }
      }
      debugPrint(
        '[QuickSplit sync] group mirror restore groups=${groups.docs.length}',
      );
    } on FirebaseException catch (error) {
      // Do not report a successful restore when the member mirror was denied:
      // proceeding would display expenses without their participants.
      debugPrint('[QuickSplit sync] group mirror read failed: ${error.code}');
      rethrow;
    }
  }

  void _appendMirrorUserAndMembership(
    List<CloudSyncChange> changes, {
    required String groupId,
    required String memberId,
    required Map<String, dynamic> profile,
    required String currentAccountId,
  }) {
    changes.add(
      CloudSyncChange(
        id: 'mirror-user-$groupId-$memberId',
        entityType: 'user',
        entityId: memberId,
        payload: {
          'name': profile['displayName'] ?? profile['name'] ?? 'Member',
          'initials': profile['initials'] ?? '?',
          'email': profile['email'],
          'phoneNumber': profile['phoneNumber'],
          'upiId': profile['upiId'],
          'isCurrentUser': memberId == currentAccountId,
          'createdAt': _stamp(profile['joinedAt']),
          'updatedAt': _stamp(profile['updatedAt']),
        },
      ),
    );
    changes.add(
      CloudSyncChange(
        id: 'mirror-membership-$groupId-$memberId',
        entityType: 'membership',
        entityId: '$groupId:$memberId',
        payload: {
          'groupId': groupId,
          'userId': memberId,
          'joinedAt': _stamp(profile['joinedAt']),
        },
      ),
    );
  }

  String _stamp(Object? value) => value is Timestamp
      ? value.toDate().toUtc().toIso8601String()
      : value is String
      ? value
      : DateTime.now().toUtc().toIso8601String();

  String _documentId(String value) => base64Url.encode(utf8.encode(value));

  Future<Map<String, Object?>> _usersReferencedBy(
    Map<String, Object?> payload,
  ) async {
    final ids = <String>{};
    for (final rows in [payload['payments'], payload['participants']]) {
      if (rows is List) {
        for (final row in rows.whereType<Map>()) {
          final id = row['userId'];
          if (id is String) ids.add(id);
        }
      }
    }
    final users = <String, Object?>{};
    final cloudIds = CloudIdRepository(_db);
    for (final cloudId in ids) {
      final localId = await cloudIds.localForCloud('user', cloudId);
      if (localId == null) continue;
      final user = await (_db.select(
        _db.users,
      )..where((row) => row.id.equals(localId))).getSingleOrNull();
      if (user == null) continue;
      users[cloudId] = {
        'name': user.name,
        'initials': user.initials,
        'phoneNumber': user.phoneNumber,
        'email': user.email,
        'upiId': user.upiId,
        'updatedAt': user.updatedAt.toUtc().toIso8601String(),
      };
    }
    return users;
  }

  Future<Map<String, Object?>?> _profileForCloudUser(String cloudId) async {
    final localId = await CloudIdRepository(_db).localForCloud('user', cloudId);
    if (localId == null) return null;
    final user = await (_db.select(
      _db.users,
    )..where((row) => row.id.equals(localId))).getSingleOrNull();
    if (user == null) return null;
    return {
      'name': user.name,
      'initials': user.initials,
      'phoneNumber': user.phoneNumber,
      'email': user.email,
      'upiId': user.upiId,
    };
  }
}
