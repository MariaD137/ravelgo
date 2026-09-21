import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireActiveAdmin, requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import { notifyUser } from "../lib/notifications";
import { containsInsensitive, paginate, paginationQuerySchema, searchQuerySchema } from "../lib/pagination";
import type { Prisma } from "@prisma/client";

export const carPaddyRouter = Router();

// Same per-route-file S3 client convention as documents.routes.ts /
// drivers.routes.ts's admin document-viewing endpoints — no shared client
// module, each route file that signs GET URLs owns one.
const s3 = new S3Client({ region: env.AWS_REGION });
const DOCUMENT_URL_EXPIRY_SECONDS = 300;

// POST /uploads/presign always issues documents-bucket keys as
// `${cognitoSub}/...` — same ownership check documents.routes.ts and
// vehicles.routes.ts already use for exactly this reason.
function ownsUploadKey(sub: string, key: string): boolean {
  return key.startsWith(`${sub}/`);
}

const submitSchema = z.object({
  plateNumber: z.string().min(1),
  // Both optional at the API layer so an older client (or the existing
  // plateNumber-only test coverage) keeps working unchanged — the Admin App
  // has nothing to review without them, but the backend doesn't hard-require
  // what it didn't before this gap was closed.
  renewalDate: z.coerce.date().optional(),
  fileKey: z.string().min(1).optional(),
});

// Driver: submit a Car Paddy (vehicle license renewal) request. Gated on the
// same admin-approved ACTIVE status as ride/delivery matching and rental
// listing — a PENDING_REVIEW driver isn't yet an approved provider.
carPaddyRouter.post("/car-paddy", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = submitSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  if (parsed.data.fileKey && !ownsUploadKey(req.user!.sub, parsed.data.fileKey)) {
    return res.status(403).json({ error: "Uploaded file does not belong to the calling user" });
  }

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });
  if (driver.status !== "ACTIVE") {
    return res.status(409).json({ error: "Your account must be approved before you can submit a Car Paddy request." });
  }

  const request = await prisma.carPaddyRequest.create({
    data: {
      driverId: driver.id,
      plateNumber: parsed.data.plateNumber,
      renewalDate: parsed.data.renewalDate,
      fileKey: parsed.data.fileKey,
    },
  });
  res.status(201).json(request);
});

// Admin: list all Car Paddy requests, optionally narrowed by a ?q= search
// against the plate number or the driver's name/email.
carPaddyRouter.get("/car-paddy", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = paginationQuerySchema.merge(searchQuerySchema).safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, q } = parsed.data;
  const where: Prisma.CarPaddyRequestWhereInput = q
    ? {
        OR: [
          { plateNumber: containsInsensitive(q) },
          { driver: { user: { firstName: containsInsensitive(q) } } },
          { driver: { user: { lastName: containsInsensitive(q) } } },
          { driver: { user: { email: containsInsensitive(q) } } },
        ],
      }
    : {};

  const [requests, total] = await Promise.all([
    prisma.carPaddyRequest.findMany({
      where,
      include: { driver: { include: { user: true } } },
      orderBy: { submittedAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.carPaddyRequest.count({ where }),
  ]);
  res.json(paginate(requests, total, page, pageSize));
});

// Admin: a short-lived signed URL to view the renewal document/receipt
// attached to a Car Paddy request — mirrors GET
// /drivers/:driverId/documents/:documentId/url exactly (same bucket, same
// expiry, same on-demand-never-persisted pattern). The stored fileKey is
// never returned to the client as a usable URL anywhere.
carPaddyRouter.get(
  "/car-paddy/:id/document-url",
  requireAuth,
  requireAdminPermission("drivers:write"),
  async (req, res) => {
    const request = await prisma.carPaddyRequest.findUnique({ where: { id: req.params.id } });
    if (!request) return res.status(404).json({ error: "Car Paddy request not found" });
    if (!request.fileKey) {
      return res.status(404).json({ error: "This request has no supporting document uploaded." });
    }
    if (!env.DOCUMENTS_BUCKET) {
      return res.status(503).json({ error: "Document storage is not configured." });
    }

    let url: string;
    try {
      url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: env.DOCUMENTS_BUCKET, Key: request.fileKey }), {
        expiresIn: DOCUMENT_URL_EXPIRY_SECONDS,
      });
    } catch (err) {
      console.error("Failed to sign Car Paddy document URL", err);
      return res.status(502).json({ error: "Unable to open this document right now. Please try again." });
    }

    res.json({ url, expiresIn: DOCUMENT_URL_EXPIRY_SECONDS });
  },
);

const decisionSchema = z
  .object({
    status: z.enum(["APPROVED", "REJECTED"]),
    // Required (and validated non-empty after trimming) only when rejecting —
    // same pattern as documents.routes.ts's reviewSchema and
    // rentals.routes.ts's decisionSchema.
    rejectionReason: z.string().trim().max(1000).optional(),
  })
  .refine((data) => data.status !== "REJECTED" || !!data.rejectionReason, {
    message: "A rejection reason is required.",
    path: ["rejectionReason"],
  });

// Admin (Super Admin / Operations Manager): approve/reject a Car Paddy request
carPaddyRouter.patch("/car-paddy/:id", requireAuth, requireAdminPermission("listings:write"), async (req, res) => {
  const parsed = decisionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.carPaddyRequest.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Car Paddy request not found" });

  const request = await prisma.carPaddyRequest.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      reviewedAt: new Date(),
      // Cleared back to null on approval so a reason never lingers on a
      // request that isn't actually rejected.
      rejectionReason: parsed.data.status === "REJECTED" ? parsed.data.rejectionReason : null,
    },
  });
  await recordAudit({
    actorSub: req.user!.sub,
    action: "CAR_PADDY_REQUEST_REVIEWED",
    entityType: "CarPaddyRequest",
    entityId: request.id,
    metadata: { status: parsed.data.status, rejectionReason: parsed.data.rejectionReason },
  });
  const driver = await prisma.driver.findUnique({ where: { id: request.driverId } });
  if (driver) {
    await notifyUser(
      driver.userId,
      "CAR_PADDY_REQUEST_REVIEWED",
      parsed.data.status === "APPROVED" ? "Car Paddy request approved" : "Car Paddy request rejected",
      parsed.data.status === "APPROVED"
        ? `Your Car Paddy renewal request for ${request.plateNumber} has been approved.`
        : `Your Car Paddy renewal request for ${request.plateNumber} was rejected: ${parsed.data.rejectionReason}`,
      { type: "CAR_PADDY_REQUEST", id: request.id },
    );
  }
  res.json(request);
});
