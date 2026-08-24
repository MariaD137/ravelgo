/**
 * End-to-end acceptance test for the driver vehicle/document verification
 * workflow — the single most important test for this feature area.
 * Walks the complete real flow through real HTTP requests against a real
 * Postgres database, exactly as a driver and an admin would experience it:
 *
 *   driver creates a vehicle (PENDING)
 *   -> uploads a vehicle photo
 *   -> uploads registration + insurance documents
 *   -> admin sees the real submission (photos, documents, vehicle)
 *   -> admin rejects the insurance document with a reason
 *   -> driver sees the rejection + reason
 *   -> driver replaces insurance (resubmit) -> PENDING again
 *   -> admin approves the vehicle
 *   -> driver sees APPROVED
 */
import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

test("full vehicle + document verification workflow: submit -> reject -> resubmit -> approve", async () => {
  const driverUser = await prisma.user.create({
    data: { cognitoSub: "e2e-driver", role: "DRIVER", firstName: "Kemi", lastName: "A", email: "kemi@example.com" },
  });
  await prisma.driver.create({ data: { userId: driverUser.id, status: "ACTIVE" } });
  const adminUser = await prisma.user.create({
    data: { cognitoSub: "e2e-admin", role: "ADMIN", firstName: "Ops", lastName: "Team", email: "ops@example.com" },
  });

  const driverToken = mockAuthAs({ sub: "e2e-driver", groups: ["Driver"] });

  // 1. Driver creates a vehicle — starts PENDING, no separate "draft" state.
  const createVehicle = await request(app)
    .post("/api/vehicles")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ brand: "Toyota", model: "Camry", colour: "Black", plateNumber: "E2E-001", year: "2022", vin: "1HGCM82633A004352", vehicleType: "SEDAN" });
  assert.equal(createVehicle.status, 201);
  assert.equal(createVehicle.body.verificationStatus, "PENDING");
  const vehicleId = createVehicle.body.id as string;

  // 2. Driver uploads a vehicle photo (fileKey namespaced to their own sub,
  // as a real presign response would produce).
  const addPhoto = await request(app)
    .post(`/api/vehicles/${vehicleId}/photos`)
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ fileKey: "e2e-driver/front.jpg", photoType: "FRONT" });
  assert.equal(addPhoto.status, 201);

  // 3. Driver uploads registration + insurance for this vehicle.
  const registration = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ title: "Registration", fileKey: "e2e-driver/registration.pdf", documentType: "VEHICLE_REGISTRATION", vehicleId });
  assert.equal(registration.status, 201);

  const insurance = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${driverToken}`)
    .send({ title: "Insurance", fileKey: "e2e-driver/insurance.pdf", documentType: "INSURANCE", vehicleId });
  assert.equal(insurance.status, 201);
  const insuranceId = insurance.body.id as string;

  restoreAuth();
  const adminToken = mockAuthAs({ sub: "e2e-admin", groups: ["Admin"] });

  // 4. Admin sees the actual submission — real vehicle, real photo, real
  // documents, not a placeholder.
  const driverRecord = await prisma.driver.findFirstOrThrow({ where: { userId: driverUser.id } });
  const adminView = await request(app).get(`/api/drivers/${driverRecord.id}`).set("Authorization", `Bearer ${adminToken}`);
  assert.equal(adminView.status, 200);
  assert.equal(adminView.body.vehicles.length, 1);
  assert.equal(adminView.body.vehicles[0].photos.length, 1);
  assert.equal(adminView.body.vehicles[0].documents.length, 2);

  // 5. Admin rejects the insurance document with a reason (mandatory).
  const rejectNoReason = await request(app)
    .patch(`/api/documents/${insuranceId}/review`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "REJECTED" });
  assert.equal(rejectNoReason.status, 400); // can't reject without a reason

  const reject = await request(app)
    .patch(`/api/documents/${insuranceId}/review`)
    .set("Authorization", `Bearer ${adminToken}`)
    .send({ status: "REJECTED", rejectionReason: "Insurance certificate is expired" });
  assert.equal(reject.status, 200);
  assert.equal(reject.body.status, "REJECTED");
  assert.equal(reject.body.reviewedById, adminUser.id);

  restoreAuth();
  const driverToken2 = mockAuthAs({ sub: "e2e-driver", groups: ["Driver"] });

  // 6. Driver sees the rejection and the real reason.
  const myDocs = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${driverToken2}`);
  const insuranceDoc = (myDocs.body as Array<{ id: string; status: string; rejectionReason: string | null }>).find(
    (d) => d.id === insuranceId,
  );
  assert.equal(insuranceDoc?.status, "REJECTED");
  assert.equal(insuranceDoc?.rejectionReason, "Insurance certificate is expired");

  // 7. Driver replaces insurance — same row, back to PENDING, reason cleared.
  const resubmit = await request(app)
    .post(`/api/documents/${insuranceId}/resubmit`)
    .set("Authorization", `Bearer ${driverToken2}`)
    .send({ fileKey: "e2e-driver/insurance-v2.pdf" });
  assert.equal(resubmit.status, 200);
  assert.equal(resubmit.body.status, "PENDING");
  assert.equal(resubmit.body.rejectionReason, null);
  assert.equal(resubmit.body.fileKey, "e2e-driver/insurance-v2.pdf");

  const allDriverDocs = await prisma.driverDocument.findMany({ where: { driverId: driverRecord.id } });
  assert.equal(allDriverDocs.length, 2); // registration + insurance — no orphan third row

  restoreAuth();
  const adminToken2 = mockAuthAs({ sub: "e2e-admin", groups: ["Admin"] });

  // 8. Admin approves the resubmitted document and the vehicle itself.
  const approveDoc = await request(app)
    .patch(`/api/documents/${insuranceId}/review`)
    .set("Authorization", `Bearer ${adminToken2}`)
    .send({ status: "APPROVED" });
  assert.equal(approveDoc.status, 200);
  assert.equal(approveDoc.body.status, "APPROVED");

  const approveVehicle = await request(app)
    .patch(`/api/vehicles/${vehicleId}/review`)
    .set("Authorization", `Bearer ${adminToken2}`)
    .send({ status: "APPROVED" });
  assert.equal(approveVehicle.status, 200);
  assert.equal(approveVehicle.body.verificationStatus, "APPROVED");

  restoreAuth();
  const driverToken3 = mockAuthAs({ sub: "e2e-driver", groups: ["Driver"] });

  // 9. Driver sees APPROVED.
  const finalVehicle = await request(app).get(`/api/vehicles/${vehicleId}`).set("Authorization", `Bearer ${driverToken3}`);
  assert.equal(finalVehicle.status, 200);
  assert.equal(finalVehicle.body.verificationStatus, "APPROVED");
  assert.equal(finalVehicle.body.verificationReason, null);
});
