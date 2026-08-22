import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import { prisma } from "../db/prisma";
import { resetDb } from "../test/helpers";
import { DriverBusyConflict, getActiveAssignment, isDriverAvailable, releaseDriver, reserveDriver } from "./driver-availability";

beforeEach(resetDb);
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

test("isDriverAvailable is true for a driver with no assignments", async () => {
  const driver = await createDriver("avail-1");
  assert.equal(await isDriverAvailable(prisma, driver.id), true);
});

test("reserveDriver claims a free driver and isDriverAvailable flips to false", async () => {
  const driver = await createDriver("avail-2");

  await prisma.$transaction(async (tx) => {
    await reserveDriver(tx, { driverId: driver.id, assignmentType: "RIDE", assignmentId: "trip-1" });
  });

  assert.equal(await isDriverAvailable(prisma, driver.id), false);
  const active = await getActiveAssignment(prisma, driver.id);
  assert.equal(active?.assignmentType, "RIDE");
  assert.equal(active?.assignmentId, "trip-1");
});

test("reserveDriver rejects a driver who already has an active assignment (app-level pre-check)", async () => {
  const driver = await createDriver("avail-3");
  await prisma.$transaction(async (tx) => {
    await reserveDriver(tx, { driverId: driver.id, assignmentType: "RIDE", assignmentId: "trip-2" });
  });

  await assert.rejects(
    prisma.$transaction(async (tx) => {
      await reserveDriver(tx, { driverId: driver.id, assignmentType: "COURIER", assignmentId: "courier-1" });
    }),
    DriverBusyConflict,
  );
});

test("releaseDriver ends the active assignment and frees the driver", async () => {
  const driver = await createDriver("avail-4");
  await prisma.$transaction(async (tx) => {
    await reserveDriver(tx, { driverId: driver.id, assignmentType: "RIDE", assignmentId: "trip-3" });
  });
  assert.equal(await isDriverAvailable(prisma, driver.id), false);

  await prisma.$transaction(async (tx) => {
    await releaseDriver(tx, { driverId: driver.id, assignmentType: "RIDE", assignmentId: "trip-3" });
  });

  assert.equal(await isDriverAvailable(prisma, driver.id), true);
  const rows = await prisma.driverAssignment.findMany({ where: { driverId: driver.id } });
  assert.equal(rows.length, 1);
  assert.equal(rows[0].status, "ENDED");
  assert.ok(rows[0].endedAt);
});

test("concurrent reserveDriver for the same driver: exactly one succeeds (database-level partial unique index)", async () => {
  const driver = await createDriver("avail-race");

  const attempt = (assignmentType: "RIDE" | "COURIER", assignmentId: string) =>
    prisma.$transaction(async (tx) => {
      await reserveDriver(tx, { driverId: driver.id, assignmentType, assignmentId });
    });

  const results = await Promise.allSettled([attempt("RIDE", "trip-race-1"), attempt("COURIER", "courier-race-1")]);
  const outcomes = results.map((r) => r.status).sort();
  assert.deepEqual(outcomes, ["fulfilled", "rejected"]);

  const active = await prisma.driverAssignment.findMany({ where: { driverId: driver.id, status: "ACTIVE" } });
  assert.equal(active.length, 1);
});
