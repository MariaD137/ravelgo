import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { blockIfAdminLacksPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { paginate, paginationQuerySchema } from "../lib/pagination";

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

// Flat rate by package size — the only pricing input a delivery has today
// (there's no pickup/dropoff geocoding on this model, unlike Trip). Server
// computes the price from this table; the client only says which size.
const PACKAGE_PRICES: Record<string, number> = {
  SMALL: 800,
  MEDIUM: 1500,
  LARGE: 2500,
};

const createCourierSchema = z.object({
  pickupAddress: z.string().min(1),
  dropoffAddress: z.string().min(1),
  packageDescription: z.string().min(1),
  packageSize: z.enum(["SMALL", "MEDIUM", "LARGE"]).default("MEDIUM"),
  recipientName: z.string().min(1),
  recipientPhone: z.string().min(1),
});

// Rider: request a courier/package delivery. estimatedFare is always
// computed server-side from packageSize — the client never asserts a price.
courierRouter.post("/courier-requests", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = createCourierSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const sender = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!sender) return res.status(404).json({ error: "Sender not found" });

  const request = await prisma.courierRequest.create({
    data: { ...parsed.data, senderId: sender.id, estimatedFare: PACKAGE_PRICES[parsed.data.packageSize] },
  });
  res.status(201).json(request);
});

// Rider: my own sent delivery requests, most recent first (delivery history).
courierRouter.get("/courier-requests/sent", requireAuth, requireRole("Rider"), async (req, res) => {
  const sender = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!sender) return res.status(404).json({ error: "Sender not found" });

  const requests = await prisma.courierRequest.findMany({
    where: { senderId: sender.id },
    include: { driver: { include: { user: true } } },
    orderBy: { requestedAt: "desc" },
  });
  res.json(requests);
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
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(paginate(requests, total, page, pageSize));
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
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count({ where }),
  ]);
  res.json(paginate(requests, total, page, pageSize));
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
  if (existing.status !== "REQUESTED" || existing.driverId) {
    return res.status(409).json({ error: "Request already matched" });
  }

  const request = await prisma.courierRequest.update({
    where: { id: req.params.id },
    data: { driverId: driver.id, status: "MATCHED" },
  });
  res.json(request);
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
    void recordAudit({
      actorSub: req.user!.sub,
      action: "COURIER_REQUEST_STATUS_OVERRIDDEN",
      entityType: "CourierRequest",
      entityId: request.id,
      metadata: { status },
    });
  }
  res.json(await withProofUrls(request));
});

// Rider or Driver: view a courier request they're party to
courierRouter.get("/courier-requests/:id", requireAuth, async (req, res) => {
  const request = await prisma.courierRequest.findUnique({
    where: { id: req.params.id },
    include: { sender: true, driver: { include: { user: true } } },
  });
  if (!request) return res.status(404).json({ error: "Courier request not found" });

  const groups = req.user!.groups;
  const isOwner =
    request.sender.cognitoSub === req.user!.sub || request.driver?.user.cognitoSub === req.user!.sub;
  if (!isOwner && !groups.includes("Admin")) {
    return res.status(403).json({ error: "Not authorized to view this request" });
  }
  res.json(await withProofUrls(request));
});

// Admin: monitor all courier requests
courierRouter.get("/courier-requests", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const [requests, total] = await Promise.all([
    prisma.courierRequest.findMany({
      include: { sender: true, driver: { include: { user: true } } },
      orderBy: { requestedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.courierRequest.count(),
  ]);
  res.json(paginate(requests, total, page, pageSize));
});
