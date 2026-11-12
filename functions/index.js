const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { logger } = require("firebase-functions");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

initializeApp();

const db = getFirestore();
const auth = getAuth();
const messaging = getMessaging();
const allowedRoles = new Set([
  "campus_security",
  "medical_services",
  "fire_services",
  "student_welfare",
  "admin",
]);

async function requireAdmin(request) {
  const claims = request.auth?.token;
  if (!claims || (claims.admin !== true && claims.role !== "admin")) {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  const adminUid = request.auth.uid;
  const user = await auth.getUser(adminUid);
  const profile = await db.collection("users").doc(adminUid).get();
  const data = profile.data() || {};
  const legacyBootstrap =
    profile.exists &&
    !Object.hasOwn(data, "accountStatus") &&
    !Object.hasOwn(data, "isVerified");
  if (
    user.disabled ||
    (!legacyBootstrap &&
      (data.accountStatus !== "active" ||
        data.isVerified !== true ||
        data.role !== "admin"))
  ) {
    throw new HttpsError(
      "permission-denied",
      "An active, manually verified administrator account is required.",
    );
  }
  return adminUid;
}

exports.manageUserAccount = onCall(
  { region: "africa-south1" },
  async (request) => {
    const adminUid = await requireAdmin(request);
    const { uid, action, role } = request.data || {};
    if (typeof uid !== "string" || !uid || uid.length > 128) {
      throw new HttpsError("invalid-argument", "A valid user UID is required.");
    }
    if (!["approve", "suspend", "reactivate", "setRole"].includes(action)) {
      throw new HttpsError("invalid-argument", "Unsupported account action.");
    }
    if (action === "setRole" && !["student", ...allowedRoles].includes(role)) {
      throw new HttpsError("invalid-argument", "Unsupported account role.");
    }
    if (uid === adminUid && (action === "suspend" || (action === "setRole" && role !== "admin"))) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot suspend or remove administrator access from your own account.",
      );
    }

    const profileRef = db.collection("users").doc(uid);
    const profileSnapshot = await profileRef.get();
    if (!profileSnapshot.exists) {
      throw new HttpsError("not-found", "The user's SafeCampus profile was not found.");
    }
    const user = await auth.getUser(uid);
    const updatedAt = FieldValue.serverTimestamp();

    switch (action) {
      case "approve":
        if (profileSnapshot.get("accountStatus") === "suspended") {
          throw new HttpsError(
            "failed-precondition",
            "Reactivate a suspended account separately before approving it.",
          );
        }
        if (
          (profileSnapshot.get("accountType") === "student" ||
            (!profileSnapshot.get("accountType") &&
              typeof profileSnapshot.get("studentNumber") === "string"))
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Student accounts activate automatically after university email verification; only staff requests are manually approved.",
          );
        }
        const approvalUpdate = {
          accountStatus: "active",
          isVerified: true,
          verifiedAt: updatedAt,
          verifiedBy: adminUid,
          updatedAt,
        };
        if (user.customClaims?.admin === true || user.customClaims?.role === "admin") {
          approvalUpdate.role = "admin";
        }
        await profileRef.update(approvalUpdate);
        break;
      case "suspend":
        await profileRef.update({
          accountStatus: "suspended",
          updatedAt,
        });
        await auth.updateUser(uid, { disabled: true });
        await auth.revokeRefreshTokens(uid);
        break;
      case "reactivate":
        if (profileSnapshot.get("isVerified") !== true) {
          throw new HttpsError(
            "failed-precondition",
            "Verify this account before reactivating it.",
          );
        }
        await auth.updateUser(uid, { disabled: false });
        await profileRef.update({
          accountStatus: "active",
          updatedAt,
        });
        break;
      case "setRole": {
        if (
          role !== "student" &&
          (profileSnapshot.get("accountStatus") !== "active" ||
            profileSnapshot.get("isVerified") !== true)
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Approve and verify the account before assigning a staff role.",
          );
        }
        const claims = { ...(user.customClaims || {}) };
        if (role === "student") {
          delete claims.role;
          delete claims.admin;
        } else {
          claims.role = role;
          if (role === "admin") {
            claims.admin = true;
          } else {
            delete claims.admin;
          }
        }
        await auth.setCustomUserClaims(uid, claims);
        await profileRef.update({ role, updatedAt });
        await auth.revokeRefreshTokens(uid);
        break;
      }
    }

    logger.info("Administrator updated a SafeCampus account.", {
      adminUid,
      targetUid: uid,
      action,
      role: action === "setRole" ? role : undefined,
    });
    return { success: true };
  },
);

exports.deleteStudentAccount = onCall(
  { region: "africa-south1", maxInstances: 3 },
  async (request) => {
    const adminUid = await requireAdmin(request);
    const { uid } = request.data || {};
    if (typeof uid !== "string" || !uid || uid.length > 128) {
      throw new HttpsError("invalid-argument", "A valid user UID is required.");
    }
    if (uid === adminUid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot delete your own administrator account.",
      );
    }

    const profileRef = db.collection("users").doc(uid);
    const profileSnapshot = await profileRef.get();
    if (!profileSnapshot.exists) {
      throw new HttpsError("not-found", "The user's SafeCampus profile was not found.");
    }
    const profile = profileSnapshot.data() || {};
    if (
      profile.role === "admin" ||
      (profile.role && profile.role !== "student") ||
      profile.accountType === "staff_request"
    ) {
      throw new HttpsError(
        "failed-precondition",
        "This action is only for student accounts. Suspend staff accounts instead.",
      );
    }

    let targetUser = null;
    try {
      targetUser = await auth.getUser(uid);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
    const targetRole = targetUser?.customClaims?.role;
    if (
      targetUser?.customClaims?.admin === true ||
      (targetRole && targetRole !== "student")
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Staff and administrator accounts cannot be deleted through student account management.",
      );
    }
    if (targetUser && !targetUser.disabled) {
      await auth.updateUser(uid, { disabled: true });
      await auth.revokeRefreshTokens(uid);
    }

    const recordsToAnonymize = [
      {
        collection: "incidents",
        retainedFields: [
          "reportType",
          "category",
          "recipientTeams",
          "status",
          "createdAt",
          "updatedAt",
          "acknowledgedAt",
          "dispatchedAt",
          "resolvedAt",
          "acknowledgedBy",
          "dispatchedBy",
          "resolvedBy",
          "campus",
        ],
      },
      {
        collection: "emergency_alerts",
        retainedFields: ["status", "createdAt", "updatedAt"],
      },
      {
        collection: "incident_reports",
        retainedFields: ["category", "status", "createdAt", "updatedAt"],
      },
    ];

    for (const { collection, retainedFields } of recordsToAnonymize) {
      const records = await db
        .collection(collection)
        .where("userId", "==", uid)
        .get();
      for (let start = 0; start < records.docs.length; start += 450) {
        const batch = db.batch();
        for (const record of records.docs.slice(start, start + 450)) {
          const original = record.data();
          const anonymized = Object.fromEntries(
            retainedFields
              .filter((field) => Object.hasOwn(original, field))
              .map((field) => [field, original[field]]),
          );
          anonymized.personalDataRemovedAt = FieldValue.serverTimestamp();
          batch.set(record.ref, anonymized);
        }
        await batch.commit();
      }
    }

    for (const tokenCollection of ["user_tokens", "staff_tokens"]) {
      const devices = await db
        .collection(tokenCollection)
        .doc(uid)
        .collection("devices")
        .get();
      for (let start = 0; start < devices.docs.length; start += 450) {
        const batch = db.batch();
        for (const device of devices.docs.slice(start, start + 450)) {
          batch.delete(device.ref);
        }
        await batch.commit();
      }
    }

    if (targetUser) {
      await auth.deleteUser(uid);
    }
    await profileRef.delete();

    logger.info("Administrator deleted a student account and anonymized records.", {
      adminUid,
      targetUid: uid,
    });
    return { success: true };
  },
);

exports.sendCampusBroadcast = onCall(
  { region: "africa-south1", maxInstances: 5 },
  async (request) => {
    const adminUid = await requireAdmin(request);
    const { title, body } = request.data || {};
    if (
      typeof title !== "string" ||
      title.trim().length < 3 ||
      title.trim().length > 100 ||
      typeof body !== "string" ||
      body.trim().length < 3 ||
      body.trim().length > 1000
    ) {
      throw new HttpsError(
        "invalid-argument",
        "Title must be 3-100 characters and message 3-1000 characters.",
      );
    }

    const snapshot = await db.collectionGroup("devices").get();
    const deviceDocs = snapshot.docs.filter((doc) =>
      doc.ref.path.startsWith("user_tokens/"),
    );
    const recipients = [];
    for (const doc of deviceDocs) {
      const uid = doc.ref.parent.parent?.id;
      const token = doc.get("fcmToken");
      if (!uid || typeof token !== "string" || !token) continue;
      try {
        const recipient = await auth.getUser(uid);
        if (!recipient.disabled) recipients.push({ token, ref: doc.ref });
      } catch (error) {
        if (error.code === "auth/user-not-found") {
          await doc.ref.delete();
          continue;
        }
        throw error;
      }
    }
    if (recipients.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "No active user notification devices are registered.",
      );
    }

    let sent = 0;
    let failed = 0;
    for (let start = 0; start < recipients.length; start += 500) {
      const batch = recipients.slice(start, start + 500);
      const result = await messaging.sendEachForMulticast({
        notification: { title: title.trim(), body: body.trim() },
        data: { type: "campus_broadcast" },
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
        tokens: batch.map((entry) => entry.token),
      });
      sent += result.successCount;
      failed += result.failureCount;
      const staleTokens = [];
      result.responses.forEach((response, index) => {
        if (
          !response.success &&
          [
            "messaging/invalid-registration-token",
            "messaging/registration-token-not-registered",
          ].includes(response.error?.code)
        ) {
          staleTokens.push(batch[index].ref.delete());
        }
      });
      await Promise.all(staleTokens);
    }

    logger.info("Campus broadcast delivery completed.", {
      adminUid,
      sent,
      failed,
    });
    if (failed > 0) {
      throw new HttpsError(
        "internal",
        `Broadcast sent to ${sent} devices; ${failed} deliveries failed.`,
      );
    }
    return { sent };
  },
);

exports.notifyRespondersOnIncident = onDocumentCreated(
  {
    document: "incidents/{incidentId}",
    region: "africa-south1",
    retry: true,
    maxInstances: 10,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.error("Incident-created event had no document snapshot.", {
        eventId: event.id,
      });
      return;
    }

    const incident = snapshot.data();
    const recipientTeams = incident.recipientTeams;
    if (!Array.isArray(recipientTeams) || recipientTeams.length === 0) {
      logger.error("Incident has no responder teams.", {
        incidentId: event.params.incidentId,
      });
      return;
    }

    const roles = [...new Set([...recipientTeams, "admin"])].filter((role) =>
      allowedRoles.has(role),
    );
    const tokenSnapshot = await db
      .collectionGroup("devices")
      .where("role", "in", roles)
      .get();

    const candidates = tokenSnapshot.docs.filter((doc) => {
      const uid = doc.ref.parent.parent?.id;
      return (
        typeof uid === "string" &&
        typeof doc.get("fcmToken") === "string" &&
        roles.includes(doc.get("role"))
      );
    });

    const eligibleTokens = [];
    for (const tokenDoc of candidates) {
      const uid = tokenDoc.ref.parent.parent.id;
      const registeredRole = tokenDoc.get("role");
      let staffUser;
      try {
        staffUser = await auth.getUser(uid);
      } catch (error) {
        if (error.code === "auth/user-not-found") {
          await tokenDoc.ref.delete();
          continue;
        }
        throw error;
      }

      const claims = staffUser.customClaims || {};
      if (staffUser.disabled) continue;
      const hasRole =
        claims.role === registeredRole ||
        (registeredRole === "admin" &&
          (claims.role === "admin" || claims.admin === true));
      if (!hasRole) {
        await tokenDoc.ref.delete();
        continue;
      }
      eligibleTokens.push({
        token: tokenDoc.get("fcmToken"),
        ref: tokenDoc.ref,
      });
    }

    if (eligibleTokens.length === 0) {
      logger.warn("No eligible responder devices are registered.", {
        incidentId: event.params.incidentId,
        recipientTeams,
      });
      return;
    }

    const title =
      incident.reportType === "sos"
        ? "SafeCampus SOS alert"
        : `SafeCampus incident: ${incident.category || "New report"}`;
    const message = {
      notification: {
        title,
        body: "A new report is waiting. Open SafeCampus to review and respond.",
      },
      data: {
        incidentId: event.params.incidentId,
        reportType: String(incident.reportType || "incident"),
        category: String(incident.category || "Incident"),
      },
      android: {
        priority: "high",
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    };

    let sent = 0;
    let failed = 0;
    for (let start = 0; start < eligibleTokens.length; start += 500) {
      const batch = eligibleTokens.slice(start, start + 500);
      const result = await messaging.sendEachForMulticast({
        ...message,
        tokens: batch.map((entry) => entry.token),
      });
      sent += result.successCount;
      failed += result.failureCount;

      const staleTokens = [];
      result.responses.forEach((response, index) => {
        if (
          !response.success &&
          [
            "messaging/invalid-registration-token",
            "messaging/registration-token-not-registered",
          ].includes(response.error?.code)
        ) {
          staleTokens.push(batch[index].ref.delete());
        }
      });
      await Promise.all(staleTokens);
    }

    logger.info("Responder notification delivery completed.", {
      incidentId: event.params.incidentId,
      recipientTeams,
      sent,
      failed,
    });
    if (failed > 0) {
      throw new Error(
        `Firebase Cloud Messaging failed to deliver ${failed} notification(s) for incident ${event.params.incidentId}.`,
      );
    }
  },
);
