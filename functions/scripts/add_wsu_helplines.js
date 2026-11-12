const { applicationDefault, initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT || "safecampus-1f0a3",
});

const helplines = [
  { name: "LifeLine", phone: "0861 322 322" },
  { name: "SADAG", phone: "0800 567 567" },
  { name: "24-hour helpline", phone: "0800 456 789" },
  { name: "GBV", phone: "0800 428 428" },
  { name: "Substance abuse", phone: "0800 12 13 14" },
  { name: "Higher Health", phone: "0800 36 36 36" },
];

async function main() {
  const db = getFirestore();
  const ref = db.collection("campus_settings").doc("helplines");
  const added = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    const existing = data?.contacts ?? [];
    if (!Array.isArray(existing) || existing.some(
      (contact) => !contact || typeof contact.phone !== "string",
    )) {
      throw new Error("Existing contacts have an invalid format; no changes made.");
    }
    const numbers = new Set(
      existing.map((contact) => contact.phone.replace(/\s/g, "")),
    );
    const additions = helplines.filter(
      (contact) => !numbers.has(contact.phone.replace(/\s/g, "")),
    );
    if (additions.length > 0) {
      transaction.set(ref, {
        contacts: [...existing, ...additions],
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    return additions.length;
  });
  console.log(`Added ${added} WSU helpline(s); existing contacts were kept.`);
}

main().catch((error) => {
  console.error(`Could not add WSU helplines: ${error.message}`);
  process.exitCode = 1;
});
