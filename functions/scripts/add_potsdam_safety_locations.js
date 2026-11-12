const { applicationDefault, initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT || "safecampus-1f0a3",
});

const locations = [
  {
    id: "main_gate_security",
    name: "Main Gate Security Office",
    description: "At the main gate, near the new Engineering Building.",
  },
  {
    id: "bus_entrance_security",
    name: "Bus Entrance Security",
    description: "At the gate where the school buses enter.",
  },
  {
    id: "old_residence_security",
    name: "Old Residence Security",
    description: "At the gate of the old student residence.",
  },
  {
    id: "new_residence_security",
    name: "New Residence Security",
    description: "At the gate of the new student residence.",
  },
  {
    id: "campus_clinic",
    name: "Campus Clinic",
    description: "On campus, opposite the Sports Office.",
  },
];

async function main() {
  const ref = getFirestore().collection("campus_settings").doc("safety_locations");
  await ref.create({ locations, updatedAt: FieldValue.serverTimestamp() });
  console.log("Added five Potsdam safety locations.");
}

main().catch((error) => {
  console.error(`Could not add safety locations: ${error.message}`);
  process.exitCode = 1;
});
