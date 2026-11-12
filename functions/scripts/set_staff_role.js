const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

const projectId = process.env.GCLOUD_PROJECT || "safecampus-1f0a3";
const [uid, role] = process.argv.slice(2);
const allowedRoles = new Set([
  "campus_security",
  "medical_services",
  "fire_services",
  "student_welfare",
  "admin",
]);

if (!uid || !allowedRoles.has(role)) {
  console.error(
    "Usage: npm run set-staff-role -- <firebase-auth-uid> <campus_security|medical_services|fire_services|student_welfare|admin>",
  );
  process.exit(2);
}

initializeApp({
  credential: applicationDefault(),
  projectId,
});

async function assignRole() {
  const auth = getAuth();
  const db = getFirestore();
  const user = await auth.getUser(uid);
  const profileRef = db.collection("users").doc(uid);
  const profile = await profileRef.get();
  if (!profile.exists) {
    throw new Error(
      "The user needs a SafeCampus profile before a role can be assigned. Have them register first.",
    );
  }
  const accountType = profile.get("accountType");
  const isRequest =
    (role === "admin" && accountType === "manager_request") ||
    (role !== "admin" && accountType === "staff_request");
  if (isRequest && !user.emailVerified) {
    throw new Error(
      "The person must verify their registration email before a role is assigned.",
    );
  }

  const currentClaims = user.customClaims || {};
  const claims = { ...currentClaims, role };

  if (role === "admin") {
    claims.admin = true;
  } else {
    delete claims.admin;
  }

  const profileUpdate = {
    role,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (isRequest) {
    profileUpdate.accountStatus = "active";
    profileUpdate.isVerified = true;
    profileUpdate.verifiedAt = FieldValue.serverTimestamp();
    profileUpdate.verifiedBy = "trusted_operator";
  }
  await profileRef.update(profileUpdate);
  await auth.setCustomUserClaims(uid, claims);
  console.log(`Assigned role "${role}" to user ${uid} in project ${projectId}.`);
  console.log("The user must sign out and sign in again for the role to appear.");
}

assignRole().catch((error) => {
  console.error(`Could not assign role: ${error.message}`);
  process.exitCode = 1;
});
