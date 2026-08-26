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

async function createDriver(cognitoSub: string) {
  const user = await prisma.user.create({
    data: { cognitoSub, role: "DRIVER", firstName: "D", lastName: "R", email: `${cognitoSub}@example.com` },
  });
  return prisma.driver.create({ data: { userId: user.id } });
}

test("POST /api/documents registers a document as PENDING for the calling driver", async () => {
  await createDriver("driver-sub-1");
  const token = mockAuthAs({ sub: "driver-sub-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${token}`)
    .send({ title: "Driver's license", fileKey: "driver-sub-1/abc-license.pdf" });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING");
});

test("GET /api/documents/me only returns the calling driver's own documents", async () => {
  const driverA = await createDriver("driver-sub-2");
  const driverB = await createDriver("driver-sub-3");
  await prisma.driverDocument.create({ data: { driverId: driverA.id, title: "Mine", fileKey: "k1" } });
  await prisma.driverDocument.create({ data: { driverId: driverB.id, title: "Not mine", fileKey: "k2" } });

  const token = mockAuthAs({ sub: "driver-sub-2", groups: ["Driver"] });
  const res = await request(app).get("/api/documents/me").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].title, "Mine");
});

test("PATCH /api/documents/:id/review rejects a non-Admin caller", async () => {
  const driver = await createDriver("driver-sub-4");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k3" } });

  const token = mockAuthAs({ sub: "driver-sub-4", groups: ["Driver"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});

test("PATCH /api/documents/:id/review lets an Admin approve a document", async () => {
  const driver = await createDriver("driver-sub-5");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Doc", fileKey: "k4" } });
  await prisma.user.create({
    data: { cognitoSub: "admin-sub-1", role: "ADMIN", firstName: "A", lastName: "D", email: "admin1@example.com" },
  });

  const token = mockAuthAs({ sub: "admin-sub-1", groups: ["Admin"] });
  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "APPROVED");
});

test("POST /api/documents rejects a fileKey that wasn't issued to the caller", async () => {
  await createDriver("driver-sub-6");
  const token = mockAuthAs({ sub: "driver-sub-6", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${token}`)
    .send({ title: "License", fileKey: "someone-else-sub/stolen-license.pdf" });

  assert.equal(res.status, 403);
});

test("POST /api/documents associates a vehicle-scoped document only when the vehicle is my own", async () => {
  const driverA = await createDriver("driver-sub-7");
  await createDriver("driver-sub-8");
  const vehicle = await prisma.vehicle.create({
    data: { driverId: driverA.id, brand: "Toyota", model: "Yaris", colour: "Grey", plateNumber: "DOC-VEH-1", year: "2020" },
  });

  const token = mockAuthAs({ sub: "driver-sub-7", groups: ["Driver"] });
  const ok = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${token}`)
    .send({
      title: "Registration",
      fileKey: "driver-sub-7/reg.pdf",
      documentType: "VEHICLE_REGISTRATION",
      vehicleId: vehicle.id,
    });
  assert.equal(ok.status, 201);
  assert.equal(ok.body.vehicleId, vehicle.id);
  assert.equal(ok.body.documentType, "VEHICLE_REGISTRATION");

  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "driver-sub-8", groups: ["Driver"] });
  const forbidden = await request(app)
    .post("/api/documents")
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ title: "Registration", fileKey: "driver-sub-8/reg.pdf", vehicleId: vehicle.id });
  assert.equal(forbidden.status, 404);
});

test("PATCH /api/documents/:id/review requires a reason to reject, and records who reviewed it", async () => {
  const driver = await createDriver("driver-sub-9");
  const doc = await prisma.driverDocument.create({ data: { driverId: driver.id, title: "Insurance", fileKey: "k5" } });
  const adminUser = await prisma.user.create({
    data: { cognitoSub: "admin-sub-2", role: "ADMIN", firstName: "A", lastName: "D", email: "admin2@example.com" },
  });
  const token = mockAuthAs({ sub: "admin-sub-2", groups: ["Admin"] });

  const missingReason = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED" });
  assert.equal(missingReason.status, 400);

  const res = await request(app)
    .patch(`/api/documents/${doc.id}/review`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "REJECTED", rejectionReason: "Insurance certificate is expired" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "REJECTED");
  assert.equal(res.body.rejectionReason, "Insurance certificate is expired");
  assert.equal(res.body.reviewedById, adminUser.id);
  assert.ok(res.body.reviewedAt);
});

test("POST /api/documents/:id/resubmit only works from REJECTED, replaces the file, and clears the rejection", async () => {
  const driver = await createDriver("driver-sub-10");
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "Insurance", fileKey: "driver-sub-10/old.pdf" },
  });
  const token = mockAuthAs({ sub: "driver-sub-10", groups: ["Driver"] });

  const tooEarly = await request(app)
    .post(`/api/documents/${doc.id}/resubmit`)
    .set("Authorization", `Bearer ${token}`)
    .send({ fileKey: "driver-sub-10/new.pdf" });
  assert.equal(tooEarly.status, 409);

  await prisma.driverDocument.update({
    where: { id: doc.id },
    data: { status: "REJECTED", rejectionReason: "Expired", reviewedAt: new Date(), reviewedById: null },
  });

  const forged = await request(app)
    .post(`/api/documents/${doc.id}/resubmit`)
    .set("Authorization", `Bearer ${token}`)
    .send({ fileKey: "someone-else-sub/new.pdf" });
  assert.equal(forged.status, 403);

  const res = await request(app)
    .post(`/api/documents/${doc.id}/resubmit`)
    .set("Authorization", `Bearer ${token}`)
    .send({ fileKey: "driver-sub-10/new.pdf" });
  assert.equal(res.status, 200);
  assert.equal(res.body.status, "PENDING");
  assert.equal(res.body.fileKey, "driver-sub-10/new.pdf");
  assert.equal(res.body.rejectionReason, null);
  assert.equal(res.body.reviewedAt, null);

  const allDocsForDriver = await prisma.driverDocument.findMany({ where: { driverId: driver.id } });
  assert.equal(allDocsForDriver.length, 1); // same row reused, no orphan duplicate
});

test("POST /api/documents/:id/resubmit 404s for another driver's document", async () => {
  const driverA = await createDriver("driver-sub-11");
  await createDriver("driver-sub-12");
  const doc = await prisma.driverDocument.create({
    data: { driverId: driverA.id, title: "License", fileKey: "driver-sub-11/x.pdf", status: "REJECTED" },
  });

  const strangerToken = mockAuthAs({ sub: "driver-sub-12", groups: ["Driver"] });
  const res = await request(app)
    .post(`/api/documents/${doc.id}/resubmit`)
    .set("Authorization", `Bearer ${strangerToken}`)
    .send({ fileKey: "driver-sub-12/x.pdf" });
  assert.equal(res.status, 404);
});

test("GET /api/documents/:id/view lets the owning driver view, but not a different driver", async () => {
  const driverA = await createDriver("driver-sub-13");
  await createDriver("driver-sub-14");
  const doc = await prisma.driverDocument.create({
    data: { driverId: driverA.id, title: "License", fileKey: "driver-sub-13/license.pdf" },
  });

  const ownerToken = mockAuthAs({ sub: "driver-sub-13", groups: ["Driver"] });
  const ownRes = await request(app).get(`/api/documents/${doc.id}/view`).set("Authorization", `Bearer ${ownerToken}`);
  assert.equal(ownRes.status, 200);
  assert.match(ownRes.body.viewUrl, /^https:\/\//);

  restoreAuth();
  const strangerToken = mockAuthAs({ sub: "driver-sub-14", groups: ["Driver"] });
  const strangerRes = await request(app)
    .get(`/api/documents/${doc.id}/view`)
    .set("Authorization", `Bearer ${strangerToken}`);
  assert.equal(strangerRes.status, 403);
});

test("GET /api/documents/:id/view lets an Admin view any driver's document", async () => {
  const driver = await createDriver("driver-sub-15");
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "License", fileKey: "driver-sub-15/license.pdf" },
  });

  const adminToken = mockAuthAs({ sub: "admin-sub-3", groups: ["Admin"] });
  const res = await request(app).get(`/api/documents/${doc.id}/view`).set("Authorization", `Bearer ${adminToken}`);
  assert.equal(res.status, 200);
  assert.match(res.body.viewUrl, /^https:\/\//);
});

test("GET /api/documents/:id/view 404s when no file has been uploaded yet", async () => {
  const driver = await createDriver("driver-sub-16");
  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: "Background Check", status: "NOT_UPLOADED" },
  });

  const token = mockAuthAs({ sub: "driver-sub-16", groups: ["Driver"] });
  const res = await request(app).get(`/api/documents/${doc.id}/view`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 404);
});
