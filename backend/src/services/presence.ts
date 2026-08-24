/**
 * Driver online/offline presence.
 *
 * The backend is the source of truth for a driver's online state — not the
 * Flutter client's local widget state. `Driver.isOnline` / `lastOnlineAt`
 * give an O(1) read for the admin fleet list; `DriverOnlineSession` is the
 * append-only log used to compute actual online *duration* for a driver's
 * own daily summary (see getOnlineHoursToday below).
 */

import { prisma } from "../db/prisma";
import { Errors } from "../lib/errors";
import type { DriverStatus } from "@prisma/client";

/**
 * Enforce who is allowed to go online. Approval state (§PENDING_REVIEW →
 * ACTIVE → SUSPENDED) already exists on Driver.status — presence just reads
 * it, it does not duplicate or replace that state machine.
 */
function assertCanGoOnline(status: DriverStatus) {
  if (status === "PENDING_REVIEW") {
    throw Errors.authorization("Your account is still pending review — you can't go online yet.");
  }
  if (status === "SUSPENDED") {
    throw Errors.authorization("Your account is suspended — you can't go online. Contact support.");
  }
}

/**
 * Toggle a driver's presence. Idempotent: calling goOnline while already
 * online (or goOffline while already offline) is a no-op on the session
 * log, not a duplicate row — this is what protects against double-tap /
 * retried requests creating two open sessions for the same driver.
 */
export async function setDriverOnline(driverId: string, status: DriverStatus, isOnline: boolean) {
  if (isOnline) assertCanGoOnline(status);

  return prisma.$transaction(async (tx) => {
    const driver = await tx.driver.findUniqueOrThrow({ where: { id: driverId } });
    const now = new Date();

    if (isOnline && !driver.isOnline) {
      await tx.driverOnlineSession.create({ data: { driverId, startedAt: now } });
    } else if (!isOnline && driver.isOnline) {
      const openSession = await tx.driverOnlineSession.findFirst({
        where: { driverId, endedAt: null },
        orderBy: { startedAt: "desc" },
      });
      // Belt-and-suspenders: isOnline=true should always imply an open
      // session (they're only ever flipped together, right below), but if
      // they've ever drifted, closing is still a no-op rather than a crash.
      if (openSession) {
        await tx.driverOnlineSession.update({ where: { id: openSession.id }, data: { endedAt: now } });
      }
    }

    return tx.driver.update({
      where: { id: driverId },
      data: { isOnline, lastOnlineAt: now },
    });
  });
}

/**
 * Sum of all online session time for `driverId` that falls within "today"
 * (server local day), including the still-open session if the driver is
 * currently online. Computed from persisted DriverOnlineSession rows only
 * — never fabricated from a timer or from isOnline alone.
 */
export async function getOnlineHoursToday(driverId: string, now: Date = new Date()): Promise<number> {
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  const sessions = await prisma.driverOnlineSession.findMany({
    where: {
      driverId,
      startedAt: { lt: now },
      OR: [{ endedAt: null }, { endedAt: { gt: startOfDay } }],
    },
  });

  const totalMs = sessions.reduce((sum, session) => {
    const start = session.startedAt > startOfDay ? session.startedAt : startOfDay;
    const end = session.endedAt && session.endedAt < now ? session.endedAt : now;
    return sum + Math.max(0, end.getTime() - start.getTime());
  }, 0);

  return totalMs / (1000 * 60 * 60);
}
