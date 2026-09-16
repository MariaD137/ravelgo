import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb, mockCognitoAdminUserStatus } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function seedUser(cognitoSub: string, email: string) {
  return prisma.user.create({
    data: { cognitoSub, role: "RIDER", firstName: "Ada", lastName: "Guest", email },
  });
}

async function seedListing(hostId: string, overrides: Partial<{ status: "PENDING_APPROVAL" | "APPROVED" | "REJECTED"; pricePerNight: number; maxGuests: number }> = {}) {
  return prisma.propertyListing.create({
    data: {
      hostId,
      title: "Cozy 1-Bedroom in Lekki",
      address: "14 Admiralty Way, Lekki, Lagos",
      pricePerNight: 45000,
      maxGuests: 2,
      status: "APPROVED",
      ...overrides,
    },
  });
}

test("POST /stays creates a listing that starts PENDING_APPROVAL", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  const token = mockAuthAs({ sub: "stays-host-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/stays")
    .set("Authorization", `Bearer ${token}`)
    .send({ title: "Studio near VI", address: "22 Adeola Odeku St, Lagos", pricePerNight: 30000 });

  assert.equal(res.status, 201);
  assert.equal(res.body.status, "PENDING_APPROVAL");
  assert.equal(res.body.hostId, host.id);
});

test("GET /stays only shows APPROVED listings to a non-admin", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  await seedListing(host.id, { status: "APPROVED" });
  await seedListing(host.id, { status: "PENDING_APPROVAL" });
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  const res = await request(app).get("/api/stays").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 1);
  assert.equal(res.body.data[0].status, "APPROVED");
});

test("GET /stays shows every listing to an admin", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  await seedListing(host.id, { status: "APPROVED" });
  await seedListing(host.id, { status: "PENDING_APPROVAL" });
  const token = mockAuthAs({ sub: "stays-admin-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const res = await request(app).get("/api/stays").set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.length, 2);
});

test("POST /stays/:id/book computes nights and total price server-side", async () => {
  await seedUser("stays-guest-1", "guest1@example.com");
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { pricePerNight: 45000, maxGuests: 4 });
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/stays/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({
      checkIn: "2026-10-01T00:00:00.000Z",
      checkOut: "2026-10-04T00:00:00.000Z",
      guests: 2,
      // A client-supplied price here is ignored — the server uses the listing's rate.
      totalPrice: 1,
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.nights, 3);
  assert.equal(res.body.totalPrice, 135000); // 45000 * 3
  assert.equal(res.body.status, "CONFIRMED");
});

test("POST /stays/:id/book rejects a guest count over maxGuests", async () => {
  await seedUser("stays-guest-1", "guest1@example.com");
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { maxGuests: 2 });
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/stays/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ checkIn: "2026-10-01T00:00:00.000Z", checkOut: "2026-10-02T00:00:00.000Z", guests: 5 });

  assert.equal(res.status, 400);
});

test("POST /stays/:id/book rejects booking a listing that isn't APPROVED", async () => {
  await seedUser("stays-guest-1", "guest1@example.com");
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { status: "PENDING_APPROVAL" });
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  const res = await request(app)
    .post(`/api/stays/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ checkIn: "2026-10-01T00:00:00.000Z", checkOut: "2026-10-02T00:00:00.000Z", guests: 1 });

  assert.equal(res.status, 409);
});

test("PATCH /stays/:id/status lets an admin approve a listing and records an audit entry", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { status: "PENDING_APPROVAL" });
  const token = mockAuthAs({ sub: "stays-admin-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const res = await request(app)
    .patch(`/api/stays/${listing.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 200);
  assert.equal(res.body.status, "APPROVED");

  const entry = await prisma.auditLog.findFirst({ where: { entityType: "PropertyListing", entityId: listing.id } });
  assert.equal(entry?.action, "STAY_LISTING_REVIEWED");
});

test("PATCH /stays/:id/status rejects a Finance Viewer admin", async () => {
  const host = await seedUser("stays-host-2", "host2@example.com");
  const listing = await seedListing(host.id, { status: "PENDING_APPROVAL" });
  await prisma.user.create({
    data: { cognitoSub: "finance-stays", role: "ADMIN", adminRole: "FINANCE_VIEWER", firstName: "F", lastName: "V", email: "fv-stays@example.com" },
  });
  const token = mockAuthAs({ sub: "finance-stays", groups: ["Admin"] });
  mockCognitoAdminUserStatus();

  const res = await request(app)
    .patch(`/api/stays/${listing.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});

test("GET /stays exposes host email and booking count to an admin but not to a guest", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { status: "APPROVED" });
  await seedUser("stays-guest-1", "guest1@example.com");
  const guestToken = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });
  await request(app)
    .post(`/api/stays/${listing.id}/book`)
    .set("Authorization", `Bearer ${guestToken}`)
    .send({ checkIn: "2026-10-01T00:00:00.000Z", checkOut: "2026-10-02T00:00:00.000Z", guests: 1 });

  const guestView = await request(app).get("/api/stays").set("Authorization", `Bearer ${guestToken}`);
  assert.equal(guestView.body.data[0].host.email, undefined);
  assert.equal(guestView.body.data[0].bookingCount, undefined);

  restoreAuth();
  const adminToken = mockAuthAs({ sub: "stays-admin-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const adminView = await request(app).get("/api/stays").set("Authorization", `Bearer ${adminToken}`);
  const seen = adminView.body.data.find((l: { id: string }) => l.id === listing.id);
  assert.equal(seen.host.email, "host1@example.com");
  assert.equal(seen.bookingCount, 1);
});

test("GET /stays/:id/bookings lets an admin see who booked a listing", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { status: "APPROVED" });
  await seedUser("stays-guest-1", "guest1@example.com");
  const guestToken = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });
  await request(app)
    .post(`/api/stays/${listing.id}/book`)
    .set("Authorization", `Bearer ${guestToken}`)
    .send({ checkIn: "2026-10-01T00:00:00.000Z", checkOut: "2026-10-02T00:00:00.000Z", guests: 1 });

  restoreAuth();
  const adminToken = mockAuthAs({ sub: "stays-admin-1", groups: ["Admin"] });
  mockCognitoAdminUserStatus();
  const res = await request(app).get(`/api/stays/${listing.id}/bookings`).set("Authorization", `Bearer ${adminToken}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].guest.email, "guest1@example.com");
});

test("GET /stays/:id/bookings rejects a non-admin caller", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { status: "APPROVED" });
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  const res = await request(app).get(`/api/stays/${listing.id}/bookings`).set("Authorization", `Bearer ${token}`);
  assert.equal(res.status, 403);
});

test("PATCH /stays/:id/status rejects a non-admin caller", async () => {
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id, { status: "PENDING_APPROVAL" });
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  const res = await request(app)
    .patch(`/api/stays/${listing.id}/status`)
    .set("Authorization", `Bearer ${token}`)
    .send({ status: "APPROVED" });

  assert.equal(res.status, 403);
});

test("GET /stays/bookings/mine returns only the caller's bookings", async () => {
  await seedUser("stays-guest-1", "guest1@example.com");
  const host = await seedUser("stays-host-1", "host1@example.com");
  const listing = await seedListing(host.id);
  const token = mockAuthAs({ sub: "stays-guest-1", groups: ["Rider"] });

  await request(app)
    .post(`/api/stays/${listing.id}/book`)
    .set("Authorization", `Bearer ${token}`)
    .send({ checkIn: "2026-10-01T00:00:00.000Z", checkOut: "2026-10-02T00:00:00.000Z", guests: 1 });

  const res = await request(app)
    .get("/api/stays/bookings/mine")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].property.id, listing.id);
});
