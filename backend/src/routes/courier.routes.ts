import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { blockIfAdminLacksPermission, requireActiveAdmin } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { notifyUser, type NotificationType } from "../lib/notifications";
import { containsInsensitive, csvList, inFilter, paginate, paginationQuerySchema, searchQuerySchema } from "../lib/pagination";
import type { Prisma } from "@prisma/client";
import { getLatestDriverLocation, locationFreshness } from "../realtime/hub";
import { haversineKm, isValidCoordinate } from "../lib/geo";
import { serializeCourierRequest } from "../lib/courier-view";
import { LEGACY_PACKAGE_PRICES, quoteDelivery } from "../services/delivery-pricing";
import { getPricingPolicy } from "../lib/pricing-policy";
import { recordDriverCompensationCharge } from "../services/ledger";
import { MAX_FINAL_FARE_MULTIPLIER, MIN_FINAL_FARE_MULTIPLIER } from "../lib/money";
import { driverEligibleForNewDelivery, findEligibleDriversForNewDelivery } from "../lib/driver-conflicts";

export const courierRouter = Router();

const s3 = new S3Client({ region: env.AWS_REGION });

// Attaches short-lived, signed GET URLs for the proof-of-delivery photo/
// signature (if present) so a client can display them without the documents
// bucket ever being public. Keys stay private; only the presigned URL leaks,
// and only to someone who already has authorized access to this request.
async function withProofUrls<T extends { deliveryPhotoKey: string | null; recipientSignatureKey: string | null }>(
  request: T,
): Promise<T & { deliveryPhotoUrl: string | null; recipientSignatureUrl: string | null }> {
  const sign = async (key: string | null) => {
    if (!key || !env.DOCUMENTS_BUCKET) return null;
    return getSignedUrl(s3, new GetObjectCommand({ Bucket: env.DOCUMENTS_BUCKET, Key: key }), { expiresIn: 900 });
  };
  const [deliveryPhotoUrl, recipientSignatureUrl] = await Promise.all([
    sign(request.deliveryPhotoKey),
    sign(request.recipientSignatureKey),
  ]);
  return { ...request, deliveryPhotoUrl, recipientSignatureUrl };
}

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

// A sender may cancel their own delivery request only before a driver has
// physically picked the package up — mirrors riderMayCancel() in
// services/trip-status.ts for the same reason (Trip and CourierRequest have
// parallel REQUESTED -> MATCHED -> ... -> CANCELLED state machines).
function courierMayCancel(status: string): boolean {
  return status === "REQUESTED" || status === "MATCHED";
}

// Attaches the courier's CURRENT location to a single request, for tracking.
// Reuses the exact same driver GPS feed as the admin Live Map's Packages view
// (realtime/hub.ts) — a package has no location of its own, only whichever
// driver currently has it — so this is never a second tracking system, and
// never a fabricated position. Omitted (null) until that driver has reported
// at least one coordinate, or once the request has no assigned driver.
function withCourierLocation<T extends { driverId: string | null }>(
  request: T,
): T & { courierLat: number | null; courierLng: number | null; courierLocationUpdatedAt: string | null; courierPresence: "LIVE" | "STALE" | null } {
  const loc = request.driverId ? getLatestDriverLocation(request.driverId) : undefined;
  return {
    ...request,
    courierLat: loc?.lat ?? null,
    courierLng: loc?.lng ?? null,
    courierLocationUpdatedAt: loc?.updatedAt ?? null,
    courierPresence: loc ? locationFreshness(loc.updatedAt) : null,
  };
}

const coord = z.number().finite();
const createCourierSchema = z.object({
  pickupAddress: z.string().min(1),
  dropoffAddress: z.string().min(1),
  packageDescription: z.string().min(1),
  packageSize: z.enum(["SMALL", "MEDIUM", "LARGE"]).default("MEDIUM"),
  // The delivery vehicle class to price against (services/delivery-pricing.ts).
  // Optional so an older client build that never sends one still works,
  // falling back to the legacy flat packageSize table below.
  deliveryVehicleClass: z.enum(["BIKE", "CAR", "SUV", "VAN"]).optional(),
  recipientName: z.string().min(1),
  recipientPhone: z.string().min(1),
  // Resolved by the sender's Places-backed address search — optional so a
  // client that only ever sends free text (or an older app build) still
  // works exactly as before; the pin is simply omitted, never guessed.
  pickupLat: coord.min(-90).max(90).optional(),
  pickupLng: coord.min(-180).max(180).optional(),
  dropoffLat: coord.min(-90).max(90).optional(),
  dropoffLng: coord.min(-180).max(180).optional(),
});

// Rider: request a courier/package delivery. estimatedFare is always
// computed server-side — from the deliveryVehicleClass rate card + real
// distance when both pickup/dropoff coordinates are given, else the legacy
// flat packageSize table — the client never asserts a price.
courierRouter.post("/courier-requests", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = createCourierSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const sender = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!sender) return res.status(404).json({ error: "Sender not found" });

  const { pickupLat, pickupLng, dropoffLat, dropoffLng, deliveryVehicleClass, ...rest } = parsed.data;
  const pickup = pickupLat != null && pickupLng != null && isValidCoordinate({ lat: pickupLat, lng: pickupLng });
  const dropoff = dropoffLat != null && dropoffLng != null && isValidCoordinate({ lat: dropoffLat, lng: dropoffLng });

  let estimatedFare: number;
  let resolvedVehicleClass: typeof deliveryVehicleClass;
  if (deliveryVehicleClass && pickup && dropoff) {
    const distanceKm = haversineKm({ lat: pickupLat!, lng: pickupLng! }, { lat: dropoffLat!, lng: dropoffLng! });
    const quote = await quoteDelivery(deliveryVehicleClass, distanceKm, parsed.data.packageSize);
    estimatedFare = quote.estimatedFare;
    resolvedVehicleClass = deliveryVehicleClass;
  } else {
    // Legacy fallback: no vehicle class chosen, or no resolved coordinates
    // to price a distance against.
    estimatedFare = LEGACY_PACKAGE_PRICES[parsed.data.packageSize];
    resolvedVehicleClass = undefined;
  }

  const request = await prisma.courierRequest.create({
    data: {
      ...rest,
      senderId: sender.id,
      deliveryVehicleClass: resolvedVehicleClass,
      estimatedFare,
      pickupLat: pickup ? pickupLat : undefined,
      pickupLng: pickup ? pickupLng : undefined,
      dropoffLat: dropoff ? dropoffLat : undefined,
      dropoffLng: dropoff ? dropoffLng : undefined,
    },
  });

  // P2 #6: push the new delivery to every currently-eligible driver instead
  // of leaving discovery entirely to polling — admin-approved, online, and
  // not already committed to a conflicting ride/delivery (never offline,
  // suspended, pending-review, or already-engaged drivers). The body
  // deliberately carries only what's needed to decide whether to accept
  // (pickup area, price) — never the recipient's name/phone, which stays
  // behind the authenticated detail/accept endpoints. A failure here is
  // never allowed to fail the delivery itself: the request has already been
  // created and committed above, and this is a best-effort fan-out on top
  // of it, exactly like notifyUser's own internal best-effort contract.
  try {
    const eligible = await findEligibleDriversForNewDelivery();
    await Promise.all(
      eligible.map((driver) =>
        notifyUser(
          driver.userId,
          "DELIVERY_OFFERED",
          "New delivery available",
          `Pickup near ${request.pickupAddress}. Estimated fare: ${request.estimatedFare}.`,
          { type: "COURIER_REQUEST", id: request.id },
        ),
      ),
    );
  } catch (err) {
    console.error("Failed to notify eligible drivers of a new delivery", err);
  }

  res.status(201).json(serializeCourierRequest(request));
});

// Rider: my own sent delivery requests, most recent first (delivery history).
courierRouter.get("/courier-requests/sent", requireAuth, requireRole("Rider"), async (req, res) => {
  const sender = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!sender) return res.status(404).json({ error: "Sender not found" });

  const requests = await prisma.courierRequest.findMany({
    where: { senderId: sender.id },
    include: { driver: { include: { user: true, vehicles: { where: { isPrimary: true }, take: 1 } } } },
    orderBy: { requestedAt: "desc" },
  });
  res.json(requests.map(serializeCourierRequest));
});

// Driver: view unassigned courier requests to accept. Gated on the same
// admin-approved ACTIVE status as ride matching (see /drivers/me/availability)
// — being in the Driver Cognito group alone (PENDING_REVIEW) is not enough to
// do delivery work, only to apply and manage a profile.
courierRouter.get("/courier-requests/available", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  if (driver.status !== "ACTIVE") {
    return res.status(409).json({ error: "Your account is not approved for deliveries yet." });
  }

  const where = { status: "REQUESTED" as const, driverId: null };

  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      where,
      include: { sender: true },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(paginate(requests.map(serializeCourierRequest), total, page, pageSize));
});

// Driver: my own accepted/in-progress courier deliveries.
courierRouter.get("/courier-requests/mine", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const where = { driverId: driver.id };
  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      where,
      include: { sender: true },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(
    paginate(
      requests.map((r) => serializeCourierRequest(withCourierLocation(r))),
      total,
      page,
      pageSize,
    ),
  );
});

// Driver: accept a courier request. Same ACTIVE gate as above.
courierRouter.patch("/courier-requests/:id/accept", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  if (driver.status !== "ACTIVE") {
    return res.status(409).json({ error: "Your account is not approved for deliveries yet." });
  }

  const existing = await prisma.courierRequest.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Courier request not found" });

  // P0: a driver must not simultaneously hold an active ride and an active
  // delivery — checked again here (matching.ts's ride offers already exclude
  // a driver with an active delivery), since this driver could have been
  // OFFERED or accepted a ride in the time since they last polled available
  // deliveries.
  if (!(await driverEligibleForNewDelivery(driver.id))) {
    return res.status(409).json({
      error: "You already have an active ride in progress. Finish it before accepting a delivery.",
    });
  }

  // Atomic conditional update (updateMany, not findUnique-then-update): two
  // drivers hitting accept on the same request at the same instant can only
  // ever have one winner — the loser gets a clean 409 instead of a lost
  // update silently overwriting the winner's assignment.
  const { count } = await prisma.courierRequest.updateMany({
    where: { id: req.params.id, status: "REQUESTED", driverId: null },
    data: { driverId: driver.id, status: "MATCHED" },
  });
  if (count === 0) {
    return res.status(409).json({ error: "Request already matched" });
  }

  const request = await prisma.courierRequest.findUniqueOrThrow({
    where: { id: req.params.id },
    include: { sender: true },
  });
  await notifyUser(
    request.senderId,
    "DELIVERY_COURIER_ASSIGNED",
    "Courier assigned",
    "A courier has been assigned to your delivery.",
    { type: "COURIER_REQUEST", id: request.id },
  );
  res.json(serializeCourierRequest(request));
});

const updateStatusSchema = z.object({
  status: z.enum(["PICKED_UP", "IN_TRANSIT", "DELIVERED", "CANCELLED"]),
  finalFare: z.number().positive().optional(),
  // Required (and only meaningful) when status is DELIVERED — S3 keys from a
  // presigned upload via POST /uploads/presign (bucket: "documents").
  deliveryPhotoKey: z.string().min(1).optional(),
  recipientSignatureKey: z.string().min(1).optional(),
});

// Driver assigned to it, or Admin: advance courier status
courierRouter.patch("/courier-requests/:id/status", requireAuth, requireRole("Driver", "Admin"), async (req, res) => {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.courierRequest.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Courier request not found" });

  const isAdmin = req.user!.groups.includes("Admin");
  if (!isAdmin) {
    const driver = await findOwnDriver(req.user!.sub);
    if (!driver || existing.driverId !== driver.id) {
      return res.status(403).json({ error: "Not authorized to update this request" });
    }
  } else if (await blockIfAdminLacksPermission(req, res, "drivers:write")) {
    return; // 403 already written
  }

  const { status, deliveryPhotoKey, recipientSignatureKey } = parsed.data;

  // Marking DELIVERED requires proof of delivery — a photo and the
  // recipient's signature — not just a status flip.
  if (status === "DELIVERED" && (!deliveryPhotoKey || !recipientSignatureKey)) {
    return res.status(400).json({
      error: "A delivery photo and the recipient's signature are required to mark this request as delivered.",
    });
  }
  // Keys are uploaded by the caller via their own presigned URL (see
  // /uploads/presign), which always prefixes the key with the caller's own
  // Cognito sub — this rejects one caller submitting another's uploaded key.
  const expectedPrefix = `${req.user!.sub}/`;
  for (const key of [deliveryPhotoKey, recipientSignatureKey]) {
    if (key && !key.startsWith(expectedPrefix)) {
      return res.status(403).json({ error: "Uploaded file does not belong to the calling user" });
    }
  }

  // Same anchor-to-the-estimate guard trips.routes.ts already applies to
  // finalFare — a courier could otherwise bill any amount at all, with no
  // relationship to what was quoted (this delivery's commission integrity
  // depends on finalFare being a real number, not an asserted one).
  if (parsed.data.finalFare != null && !isAdmin) {
    const lower = existing.estimatedFare * MIN_FINAL_FARE_MULTIPLIER;
    const upper = existing.estimatedFare * MAX_FINAL_FARE_MULTIPLIER;
    if (parsed.data.finalFare < lower || parsed.data.finalFare > upper) {
      return res.status(422).json({
        error: {
          code: "FARE_OUT_OF_RANGE",
          message: `finalFare must be within ${MIN_FINAL_FARE_MULTIPLIER}x–${MAX_FINAL_FARE_MULTIPLIER}x the estimated fare of ${existing.estimatedFare}`,
          timestamp: new Date().toISOString(),
        },
      });
    }
  }

  const request = await prisma.courierRequest.update({
    where: { id: req.params.id },
    data: {
      status,
      finalFare: parsed.data.finalFare,
      pickedUpAt: status === "PICKED_UP" ? new Date() : undefined,
      deliveredAt: status === "DELIVERED" ? new Date() : undefined,
      deliveryPhotoKey: status === "DELIVERED" ? deliveryPhotoKey : undefined,
      recipientSignatureKey: status === "DELIVERED" ? recipientSignatureKey : undefined,
    },
  });
  if (isAdmin) {
    await recordAudit({
      actorSub: req.user!.sub,
      action: "COURIER_REQUEST_STATUS_OVERRIDDEN",
      entityType: "CourierRequest",
      entityId: request.id,
      metadata: { status },
    });
  }
  const statusNotifications: Partial<Record<typeof status, { type: NotificationType; title: string; body: string }>> = {
    PICKED_UP: { type: "DELIVERY_PICKED_UP", title: "Package picked up", body: "Your package has been picked up by the courier." },
    IN_TRANSIT: { type: "DELIVERY_IN_TRANSIT", title: "Package in transit", body: "Your package is on its way." },
    DELIVERED: { type: "DELIVERY_DELIVERED", title: "Package delivered", body: "Your package has been delivered." },
    CANCELLED: { type: "DELIVERY_CANCELLED", title: "Delivery cancelled", body: "Your delivery request was cancelled." },
  };
  const notification = statusNotifications[status];
  if (notification) {
    await notifyUser(request.senderId, notification.type, notification.title, notification.body, {
      type: "COURIER_REQUEST",
      id: request.id,
    });
    // An admin override changes the job out from under the driver actually
    // assigned to it (e.g. an admin cancels a delivery a driver already
    // picked up) — the driver needs to know too, not just the sender. A
    // driver-initiated change needs no self-notification. Reuses the same
    // notification system, no new infra.
    if (isAdmin && request.driverId) {
      const assignedDriver = await prisma.driver.findUnique({ where: { id: request.driverId } });
      if (assignedDriver) {
        await notifyUser(assignedDriver.userId, notification.type, notification.title, notification.body, {
          type: "COURIER_REQUEST",
          id: request.id,
        });
      }
    }
  }
  res.json(serializeCourierRequest(await withProofUrls(request)));
});

// Rider: cancel a delivery request they sent, before a driver has picked the
// package up. Previously there was no cancel path for the sender at all —
// only Driver/Admin could change status via the route above — so a customer
// who no longer wanted a still-REQUESTED delivery had no way to stop it.
courierRouter.post("/courier-requests/:id/cancel", requireAuth, requireRole("Rider"), async (req, res) => {
  const existing = await prisma.courierRequest.findUnique({
    where: { id: req.params.id },
    include: { sender: true },
  });
  if (!existing) return res.status(404).json({ error: "Courier request not found" });
  if (existing.sender.cognitoSub !== req.user!.sub) {
    return res.status(403).json({ error: "Not authorized to cancel this request" });
  }
  if (!courierMayCancel(existing.status)) {
    return res.status(409).json({
      error: {
        code: "COURIER_REQUEST_NOT_CANCELLABLE",
        message: `A ${existing.status} delivery request can no longer be cancelled`,
        timestamp: new Date().toISOString(),
      },
    });
  }

  // Same shape as the ride cancellation fee (trips.routes.ts): only once a
  // courier is actually assigned (MATCHED) and past the configured grace
  // period. Recorded for driver-transparency/audit; not itself collected
  // here — see the equivalent note on the ride cancellation-fee path.
  let cancellationFee = 0;
  if (existing.status === "MATCHED" && existing.driverId) {
    const policy = await getPricingPolicy();
    const elapsedSec = (Date.now() - existing.requestedAt.getTime()) / 1000;
    if (elapsedSec > policy.deliveryCancellationGraceSec) {
      cancellationFee = policy.deliveryCancellationFee;
    }
  }

  const request = await prisma.courierRequest.update({
    where: { id: existing.id },
    data: { status: "CANCELLED", cancellationFee: cancellationFee > 0 ? cancellationFee : undefined },
  });
  if (cancellationFee > 0 && request.driverId) {
    await recordDriverCompensationCharge({
      type: "CANCELLATION_FEE",
      courierRequestId: request.id,
      customerId: request.senderId,
      driverId: request.driverId,
      amount: cancellationFee,
    });
  }
  // Notify the sender too (same as trips.routes.ts's rider-initiated trip
  // cancel), so this shows up in their real notification/activity feed like
  // every other status change, not just ones someone else triggered.
  await notifyUser(request.senderId, "DELIVERY_CANCELLED", "Delivery cancelled", "Your delivery request was cancelled.", {
    type: "COURIER_REQUEST",
    id: request.id,
  });
  // A driver may already be matched to this request when the sender
  // cancels it — they need to know it's off, the same as an admin override
  // above notifies them.
  if (request.driverId) {
    const assignedDriver = await prisma.driver.findUnique({ where: { id: request.driverId } });
    if (assignedDriver) {
      await notifyUser(assignedDriver.userId, "DELIVERY_CANCELLED", "Delivery cancelled", "The sender cancelled this delivery request.", {
        type: "COURIER_REQUEST",
        id: request.id,
      });
    }
  }
  res.json(serializeCourierRequest(request));
});

// Rider or Driver: view a courier request they're party to. An ACTIVE driver
// may also view an unassigned (REQUESTED, no driverId) request's detail —
// the same eligibility /courier-requests/available already grants for the
// list, just extended to the single-record fetch a detail screen needs
// before the driver has accepted it.
courierRouter.get("/courier-requests/:id", requireAuth, async (req, res) => {
  const request = await prisma.courierRequest.findUnique({
    where: { id: req.params.id },
    include: {
      sender: true,
      driver: { include: { user: true, vehicles: { where: { isPrimary: true }, take: 1 } } },
      payment: true,
    },
  });
  if (!request) return res.status(404).json({ error: "Courier request not found" });

  const groups = req.user!.groups;
  const isAdmin = groups.includes("Admin");
  const isOwner =
    request.sender.cognitoSub === req.user!.sub || request.driver?.user.cognitoSub === req.user!.sub;
  let isEligibleToBrowse = false;
  if (!isOwner && !isAdmin && groups.includes("Driver") && request.status === "REQUESTED" && !request.driverId) {
    const driver = await findOwnDriver(req.user!.sub);
    isEligibleToBrowse = driver?.status === "ACTIVE";
  }
  if (!isOwner && !isEligibleToBrowse && !isAdmin) {
    return res.status(403).json({ error: "Not authorized to view this request" });
  }
  const body = serializeCourierRequest(withCourierLocation(await withProofUrls(request)));
  // Payment state (method/status/amount/paidAt) only for the request's own
  // sender/driver or Admin — mirrors trips.routes.ts's GET /trips/:id. This
  // is what tells the sender's DeliveryTrackingScreen whether POST
  // /courier-requests/:id/pay still needs to be offered, or the delivery is
  // already settled (charged by the driver, or paid another way).
  res.json(isOwner || isAdmin ? { ...body, payment: request.payment ?? null } : body);
});

const adminCourierQuerySchema = paginationQuerySchema.merge(searchQuerySchema).extend({
  // Optional comma-separated status filter, applied server-side (see trips).
  status: z.preprocess(
    csvList,
    z.array(z.enum(["REQUESTED", "MATCHED", "PICKED_UP", "IN_TRANSIT", "DELIVERED", "CANCELLED"])).optional(),
  ),
});

// Admin: monitor all courier requests, optionally narrowed by status and/or
// a ?q= search against the sender's/driver's name/email or the recipient's
// name.
courierRouter.get("/courier-requests", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = adminCourierQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, status, q } = parsed.data;
  const where: Prisma.CourierRequestWhereInput = {
    status: inFilter(status),
    ...(q
      ? {
          OR: [
            { recipientName: containsInsensitive(q) },
            { sender: { firstName: containsInsensitive(q) } },
            { sender: { lastName: containsInsensitive(q) } },
            { sender: { email: containsInsensitive(q) } },
            { driver: { user: { firstName: containsInsensitive(q) } } },
            { driver: { user: { lastName: containsInsensitive(q) } } },
            { driver: { user: { email: containsInsensitive(q) } } },
          ],
        }
      : {}),
  };

  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      where,
      include: { sender: true, driver: { include: { user: true, vehicles: { where: { isPrimary: true }, take: 1 } } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(paginate(requests.map(serializeCourierRequest), total, page, pageSize));
});
