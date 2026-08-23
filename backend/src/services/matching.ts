import { Prisma } from "@prisma/client";
import { prisma } from "../db/prisma";
import { reserveDriver } from "./driver-availability";

/** How long a driver has to respond to an offer before it's treated as
 * expired and re-offered to the next eligible driver. Kept short and
 * Uber-like — long enough for a real accept/decline tap, short enough that
 * a rider isn't left waiting on an unresponsive driver. */
export const OFFER_TTL_SECONDS = 20;

export class OfferNotFoundError extends Error {}
export class OfferForbiddenError extends Error {}
/** The offer exists and belongs to this driver, but can no longer be acted
 * on — already resolved (accepted/declined/expired by someone/something
 * else), or its own expiresAt has passed. Also thrown if the underlying
 * trip is no longer REQUESTED (e.g. the rider cancelled it out from under
 * the offer) even though the offer row itself might still say OFFERED. */
export class OfferNotAvailableError extends Error {}

/**
 * The real, current eligibility rule for "can this driver receive a new
 * ride offer right now": ACTIVE + online (see Driver.online's own doc
 * comment) + not already busy on a committed Ride/Courier/Rental job
 * (DriverAssignment) + not already sitting on a different unanswered offer
 * (TripOffer, status OFFERED) + not already offered *this* trip before
 * (skipped drivers stay skipped for the trip's lifetime, so a decline/
 * expiry never loops back to the same driver).
 */
async function findEligibleDriver(tx: Prisma.TransactionClient, excludeDriverIds: string[]) {
  return tx.driver.findFirst({
    where: {
      status: "ACTIVE",
      online: true,
      id: excludeDriverIds.length > 0 ? { notIn: excludeDriverIds } : undefined,
      tripsAsDriver: { none: { status: { in: ["MATCHED", "IN_PROGRESS"] } } },
      assignments: { none: { status: "ACTIVE" } },
      tripOffers: { none: { status: "OFFERED" } },
    },
    orderBy: { rating: "desc" },
  });
}

/**
 * Sends a real ride offer to the next eligible driver for [tripId] — never
 * an automatic match. Excludes every driver already offered (and every
 * driver already busy elsewhere), so repeated calls (on decline, on
 * expiry) naturally work through the eligible pool without looping back to
 * someone who already turned this trip down. Returns the created offer, or
 * null if the trip isn't REQUESTED anymore or no eligible driver exists
 * right now (the trip is simply left REQUESTED with no active offer — the
 * same honest "no driver available" outcome as before, just at the offer
 * stage instead of the match stage).
 *
 * The read (which driver is eligible) and the TripOffer insert run inside
 * one SERIALIZABLE transaction, backed by the partial unique index
 * TripOffer_driverId_offered_unique — the same two-layer concurrency
 * pattern used everywhere else in this codebase (see reserveDriver's own
 * doc comment).
 */
export async function offerNextDriver(tripId: string) {
  try {
    return await prisma.$transaction(
      async (tx) => {
        const trip = await tx.trip.findUnique({ where: { id: tripId } });
        if (!trip || trip.status !== "REQUESTED") return null;

        const alreadyOffered = await tx.tripOffer.findMany({ where: { tripId }, select: { driverId: true } });
        const driver = await findEligibleDriver(
          tx,
          alreadyOffered.map((o) => o.driverId),
        );
        if (!driver) return null;

        return tx.tripOffer.create({
          data: {
            tripId,
            driverId: driver.id,
            expiresAt: new Date(Date.now() + OFFER_TTL_SECONDS * 1000),
          },
        });
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    // P2034: lost a serialization race to another concurrent offer attempt.
    // P2002: the database-level backstop caught a driver already holding an
    // OFFERED row that the pre-check above raced past. Both mean "no offer
    // went out this attempt" — same honest outcome as no-eligible-driver.
    if (
      err instanceof Prisma.PrismaClientKnownRequestError &&
      (err.code === "P2034" || err.code === "P2002")
    ) {
      return null;
    }
    throw err;
  }
}

function loadOfferOrThrow(offerId: string, driverId: string) {
  return prisma.tripOffer.findUnique({ where: { id: offerId } }).then((offer) => {
    if (!offer) throw new OfferNotFoundError();
    if (offer.driverId !== driverId) throw new OfferForbiddenError();
    return offer;
  });
}

/**
 * The real accept step — this is the ONLY place a Trip actually becomes
 * MATCHED; there is no automatic acceptance anywhere in this codebase.
 * Atomic: the "still OFFERED and not expired" check and the write happen
 * in one conditional updateMany, so a driver who taps Accept a moment
 * after their offer expired (or after some other driver's identical
 * check-then-write, in the vanishingly unlikely event two drivers were
 * ever offered the same trip) gets a clean OfferNotAvailableError instead
 * of silently succeeding. Vehicle selection happens here, not at offer
 * time — an offer must never tie up a vehicle the driver might go on to
 * decline.
 */
export async function acceptOffer(offerId: string, driverId: string) {
  const existing = await loadOfferOrThrow(offerId, driverId);

  try {
    return await prisma.$transaction(
      async (tx) => {
        const { count } = await tx.tripOffer.updateMany({
          where: { id: offerId, status: "OFFERED", expiresAt: { gt: new Date() } },
          data: { status: "ACCEPTED", respondedAt: new Date() },
        });
        if (count === 0) throw new OfferNotAvailableError("This offer is no longer available.");

        const trip = await tx.trip.findUnique({ where: { id: existing.tripId } });
        if (!trip || trip.status !== "REQUESTED") {
          throw new OfferNotAvailableError("This trip is no longer available.");
        }

        // Prefer the driver's primary vehicle; fall back to any other of
        // theirs not already committed elsewhere — same selection as the
        // old synchronous matcher, just deferred to the moment of actual
        // commitment instead of at offer time.
        const vehicle = await tx.vehicle.findFirst({
          where: { driverId, assignments: { none: { status: "ACTIVE" } } },
          orderBy: { isPrimary: "desc" },
        });

        const updated = await tx.trip.update({
          where: { id: trip.id },
          data: { driverId, vehicleId: vehicle?.id, status: "MATCHED" },
        });

        await reserveDriver(tx, {
          driverId,
          assignmentType: "RIDE",
          assignmentId: updated.id,
          vehicleId: vehicle?.id,
        });

        return updated;
      },
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
  } catch (err) {
    // P2034: lost a serialization race (e.g. to a concurrent
    // reserveDriver for the same driver from another domain).
    // DriverBusyConflict: the driver picked up a conflicting job between
    // the offer being sent and this accept landing. Either way, the offer
    // is no longer honorable — surfaced the same way, not a 500.
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2034") {
      throw new OfferNotAvailableError("This offer conflicted with a concurrent change, it may have expired.");
    }
    throw err;
  }
}

/**
 * Declining never affects the driver's account in any way — no suspension,
 * no online/offline change, no cooldown. It just records the decision
 * (preserved for acceptance-rate reporting, §6) and hands the trip to the
 * next eligible driver, exactly like an expiry does.
 */
export async function declineOffer(offerId: string, driverId: string) {
  const existing = await loadOfferOrThrow(offerId, driverId);

  const { count } = await prisma.tripOffer.updateMany({
    where: { id: offerId, status: "OFFERED" },
    data: { status: "DECLINED", respondedAt: new Date() },
  });
  if (count === 0) throw new OfferNotAvailableError("This offer is no longer available.");

  const nextOffer = await offerNextDriver(existing.tripId);
  return { declinedOfferId: offerId, nextOffer };
}

/**
 * Lazy expiration: there is no scheduler/queue in this codebase (see
 * matchDriverToTrip's — now offerNextDriver's — own historical note on why
 * that's the right call for this MVP's traffic), so an offer's expiresAt
 * is enforced the same way Ride's whole matching step already runs: inline,
 * driven by whoever next reads relevant state. Both the offered driver's
 * own polling (GET /drivers/me/offer) and the rider's own trip polling
 * (GET /trips/:id) call this, so a stale offer gets caught and advanced to
 * the next driver within one polling interval of either side, without any
 * background process. Safe to call liberally — a no-op unless there's
 * actually an OFFERED row past its expiresAt for this trip.
 */
export interface AcceptanceStats {
  totalOffers: number;
  acceptedOffers: number;
  declinedOffers: number;
  expiredOffers: number;
  /** acceptedOffers / totalOffers — null (not 0) when the driver has never
   * had an offer resolve yet, so "no data" is never displayed as if it
   * were a 0% record. */
  acceptanceRate: number | null;
}

/**
 * Acceptance Rate = accepted offers / offers actually presented, per §6:
 * a driver performance/analytics number, never an account-status
 * mechanism (nothing here writes to Driver.status or Driver.online).
 * "Presented" means resolved one way or another — ACCEPTED, DECLINED, or
 * EXPIRED all count in the denominator (each was a real offer the driver
 * had a chance to act on); a still-OFFERED, not-yet-answered offer is
 * deliberately excluded until it resolves, so an in-flight offer can't
 * skew the rate. EXPIRED is broken out as its own field rather than
 * folded into "declined" — an expiry is not a decision the driver made.
 * Computed on read from TripOffer rows rather than a separate running
 * counter, so it can never drift out of sync with the actual offer
 * history.
 */
export async function getAcceptanceStats(driverId: string): Promise<AcceptanceStats> {
  const counts = await prisma.tripOffer.groupBy({
    by: ["status"],
    where: { driverId, status: { in: ["ACCEPTED", "DECLINED", "EXPIRED"] } },
    _count: { _all: true },
  });
  const byStatus = Object.fromEntries(counts.map((row) => [row.status, row._count._all]));
  const acceptedOffers = byStatus.ACCEPTED ?? 0;
  const declinedOffers = byStatus.DECLINED ?? 0;
  const expiredOffers = byStatus.EXPIRED ?? 0;
  const totalOffers = acceptedOffers + declinedOffers + expiredOffers;
  return {
    totalOffers,
    acceptedOffers,
    declinedOffers,
    expiredOffers,
    acceptanceRate: totalOffers > 0 ? acceptedOffers / totalOffers : null,
  };
}

export async function expireStaleOfferIfAny(tripId: string) {
  const current = await prisma.tripOffer.findFirst({ where: { tripId, status: "OFFERED" } });
  if (!current || current.expiresAt > new Date()) return null;

  const { count } = await prisma.tripOffer.updateMany({
    where: { id: current.id, status: "OFFERED" },
    data: { status: "EXPIRED", respondedAt: new Date() },
  });
  if (count === 0) return null; // someone else (accept/decline) resolved it first

  return offerNextDriver(tripId);
}
