import {createHash, randomBytes} from "crypto";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

initializeApp();
const db = getFirestore();

const tokenHash = (token: string) =>
  createHash("sha256").update(token).digest("hex");

const requireUid = (uid: string | undefined): string => {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
};

/** Creates a short-lived QR invite. The raw token is returned only to the owner. */
export const createGroupInvite = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const groupId = request.data?.groupId;
  if (typeof groupId !== "string" || !/^[0-9a-f-]{36}$/i.test(groupId)) {
    throw new HttpsError("invalid-argument", "Invalid group identifier.");
  }
  const membership = await db.doc(`groups/${groupId}/members/${uid}`).get();
  if (!membership.exists) throw new HttpsError("permission-denied", "Not a group member.");
  const group = await db.doc(`groups/${groupId}`).get();
  if (!group.exists || group.get("archived") === true) {
    throw new HttpsError("not-found", "Group is unavailable.");
  }
  const token = randomBytes(32).toString("base64url");
  const invite = db.collection("groupInvites").doc();
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  await invite.set({
    groupId,
    groupName: group.get("name"),
    tokenHash: tokenHash(token),
    active: true,
    uses: 0,
    maxUses: 1,
    expiresAt,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {invitationId: invite.id, token, groupName: group.get("name"), expiresAt: expiresAt.toISOString()};
});

/** Validates the opaque QR secret and creates membership atomically. */
export const joinGroupWithInvite = onCall(async (request) => {
  const uid = requireUid(request.auth?.uid);
  const invitationId = request.data?.invitationId;
  const token = request.data?.token;
  if (typeof invitationId !== "string" || typeof token !== "string" || token.length < 32) {
    throw new HttpsError("invalid-argument", "Invalid invitation.");
  }
  const inviteRef = db.doc(`groupInvites/${invitationId}`);
  const result = await db.runTransaction(async (transaction) => {
    const invite = await transaction.get(inviteRef);
    if (!invite.exists || invite.get("active") !== true || invite.get("tokenHash") !== tokenHash(token)) {
      throw new HttpsError("permission-denied", "Invitation is invalid or revoked.");
    }
    const expiresAt = invite.get("expiresAt")?.toDate?.();
    if (!expiresAt || expiresAt.getTime() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "Invitation has expired.");
    }
    const groupId = invite.get("groupId") as string;
    const groupRef = db.doc(`groups/${groupId}`);
    const group = await transaction.get(groupRef);
    if (!group.exists || group.get("archived") === true) {
      throw new HttpsError("not-found", "Group is unavailable.");
    }
    const membershipRef = groupRef.collection("members").doc(uid);
    const membership = await transaction.get(membershipRef);
    if (!membership.exists) {
      const uses = invite.get("uses") as number;
      const maxUses = invite.get("maxUses") as number;
      if (uses >= maxUses) throw new HttpsError("resource-exhausted", "Invitation has reached its use limit.");
      transaction.set(membershipRef, {joinedAt: FieldValue.serverTimestamp()});
      transaction.update(inviteRef, {uses: FieldValue.increment(1)});
    }
    return {groupId, groupName: group.get("name") as string};
  });
  return result;
});
