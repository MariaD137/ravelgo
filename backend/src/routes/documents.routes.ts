import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";

export const documentsRouter = Router();

// Same per-route-file S3 client convention as drivers.routes.ts's admin
// document-viewing endpoint and courier.routes.ts's proof-of-delivery URLs —
// no shared client module, each route file that signs GET URLs owns one.
const s3 = new S3Client({ region: env.AWS_REGION });
const DOCUMENT_URL_EXPIRY_SECONDS = 300;

// Driver: view my own documents
documentsRouter.get("/documents/me", requireAuth, requireRole("Driver"), async (req, res) => {
  // select: id only. This runs on every /documents/* call a driver makes —
  // an unscoped findFirst here would pull every Driver scalar, including
  // ones added by a migration this environment hasn't applied yet (P2022),
  // turning a schema change unrelated to documents into a 500 here too.
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    select: { id: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const documents = await prisma.driverDocument.findMany({ where: { driverId: driver.id } });
  res.json(documents);
});

// Driver: a short-lived signed URL to view one of MY OWN uploaded documents.
// Mirrors drivers.routes.ts's admin equivalent (GET
// /drivers/:driverId/documents/:documentId/url) exactly — same S3 bucket,
// same expiry — but scoped to the caller's own driver profile instead of
// requiring an Admin permission. The document's fileKey is never returned to
// the client as a usable URL anywhere (GET /documents/me returns only the
// raw key, which identifies but doesn't grant access to the private S3
// object) — a fresh signed URL is generated here on demand.
documentsRouter.get("/documents/:id/url", requireAuth, requireRole("Driver"), async (req, res) => {
  // select: id only. This runs on every /documents/* call a driver makes —
  // an unscoped findFirst here would pull every Driver scalar, including
  // ones added by a migration this environment hasn't applied yet (P2022),
  // turning a schema change unrelated to documents into a 500 here too.
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    select: { id: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const doc = await prisma.driverDocument.findUnique({ where: { id: req.params.id } });
  // Same 404 whether the document doesn't exist at all or belongs to a
  // different driver — this endpoint must never confirm or deny that a given
  // document ID exists for a driver other than the caller.
  if (!doc || doc.driverId !== driver.id) {
    return res.status(404).json({ error: "Document could not be found." });
  }
  if (!doc.fileKey) {
    return res.status(404).json({ error: "The document record exists, but no file has been uploaded for it." });
  }
  if (!env.DOCUMENTS_BUCKET) {
    return res.status(503).json({ error: "Document storage is not configured." });
  }

  let url: string;
  try {
    url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: env.DOCUMENTS_BUCKET, Key: doc.fileKey }), {
      expiresIn: DOCUMENT_URL_EXPIRY_SECONDS,
    });
  } catch (err) {
    console.error("Failed to sign driver's own document URL", err);
    return res.status(502).json({ error: "Unable to open this document right now. Please try again." });
  }

  res.json({ url, expiresIn: DOCUMENT_URL_EXPIRY_SECONDS });
});

const uploadSchema = z.object({
  title: z.string().min(1),
  fileKey: z.string().min(1), // S3 object key, uploaded client-side via a presigned URL
});

// Driver: register an uploaded document (the file itself goes straight to S3
// via a presigned URL obtained separately; this just records the metadata)
documentsRouter.post("/documents", requireAuth, requireRole("Driver"), async (req, res) => {
  const parsed = uploadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  // POST /uploads/presign always issues keys as `${cognitoSub}/...` — reject
  // anything else so a driver can't register another driver's real object
  // key (however hard that is to guess) or a key that was never actually
  // presigned for this caller at all.
  const expectedPrefix = `${req.user!.sub}/`;
  if (!parsed.data.fileKey.startsWith(expectedPrefix)) {
    return res.status(403).json({ error: "fileKey does not belong to the calling user" });
  }

  // select: id only. This runs on every /documents/* call a driver makes —
  // an unscoped findFirst here would pull every Driver scalar, including
  // ones added by a migration this environment hasn't applied yet (P2022),
  // turning a schema change unrelated to documents into a 500 here too.
  const driver = await prisma.driver.findFirst({
    where: { user: { cognitoSub: req.user!.sub } },
    select: { id: true },
  });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: parsed.data.title, fileKey: parsed.data.fileKey, status: "PENDING" },
  });
  res.status(201).json(doc);
});

const reviewSchema = z
  .object({
    status: z.enum(["APPROVED", "REJECTED"]),
    // Required (and validated non-empty after trimming) only when rejecting —
    // enforced below rather than with a discriminated union so the 400 names
    // the real reason instead of a generic schema-shape error.
    rejectionReason: z.string().trim().max(1000).optional(),
  })
  .refine((data) => data.status !== "REJECTED" || !!data.rejectionReason, {
    message: "A rejection reason is required.",
    path: ["rejectionReason"],
  });

// Admin: approve/reject a document. Rejecting without a reason is refused —
// the driver needs to know what to fix before resubmitting, and a resubmitted
// document is a brand-new DriverDocument row (see POST /documents above), so
// this reason never lingers on whatever the driver uploads next.
documentsRouter.patch("/documents/:id/review", requireAuth, requireAdminPermission("drivers:write"), async (req, res) => {
  const parsed = reviewSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.driverDocument.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Document could not be found." });

  const doc = await prisma.driverDocument.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      rejectionReason: parsed.data.status === "REJECTED" ? parsed.data.rejectionReason : null,
    },
  });
  // Awaited so a caller can never observe a 200 before the audit row exists —
  // recordAudit never throws, so this can't turn a real failure into one.
  await recordAudit({
    actorSub: req.user!.sub,
    action: parsed.data.status === "APPROVED" ? "DOCUMENT_APPROVED" : "DOCUMENT_REJECTED",
    entityType: "DriverDocument",
    entityId: doc.id,
    metadata: { status: parsed.data.status, rejectionReason: parsed.data.rejectionReason },
  });
  res.json(doc);
});
