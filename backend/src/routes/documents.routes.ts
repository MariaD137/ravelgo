import { GetObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { Router } from "express";
import { z } from "zod";
import { env } from "../config/env";
import { prisma } from "../db/prisma";
import { Errors } from "../lib/errors";
import { assertFileKeyOwnedByUser } from "../lib/fileKey";
import { s3 } from "../lib/s3";
import { requireAuth, requireRole } from "../middleware/auth";
import { asyncHandler } from "../middleware/async-handler";

export const documentsRouter = Router();

async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}

// Driver: view my own documents. Optional ?vehicleId= scopes to documents
// attached to one vehicle (registration/insurance/inspection); omitted
// returns everything, including driver-level docs (license, background
// check) which have no vehicleId.
documentsRouter.get("/documents/me", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const vehicleId = typeof req.query.vehicleId === "string" ? req.query.vehicleId : undefined;
  const documents = await prisma.driverDocument.findMany({
    where: { driverId: driver.id, ...(vehicleId ? { vehicleId } : {}) },
    orderBy: { updatedAt: "desc" },
  });
  res.json(documents);
}));

const documentTypeEnum = z.enum([
  "DRIVERS_LICENSE",
  "VEHICLE_REGISTRATION",
  "INSURANCE",
  "INSPECTION",
  "ROADWORTHINESS",
  "BACKGROUND_CHECK",
  "PROOF_OF_ADDRESS",
  "OTHER",
]);

const uploadSchema = z.object({
  title: z.string().min(1),
  fileKey: z.string().min(1), // S3 object key, uploaded client-side via a presigned URL
  documentType: documentTypeEnum.default("OTHER"),
  // Present for a vehicle-specific document (registration, insurance,
  // inspection); absent for a driver-level one (license, background check).
  vehicleId: z.string().optional(),
  expiryDate: z.string().optional(),
});

// Driver: register an uploaded document (the file itself goes straight to S3
// via a presigned URL obtained separately; this just records the metadata).
// fileKey ownership and (if given) vehicle ownership are both verified
// server-side — never trust either as given.
documentsRouter.post("/documents", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = uploadSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  let expiryDate: Date | undefined;
  if (parsed.data.expiryDate) {
    expiryDate = new Date(parsed.data.expiryDate);
    if (Number.isNaN(expiryDate.getTime())) {
      return res.status(400).json({ error: "expiryDate is not a valid date" });
    }
  }

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  assertFileKeyOwnedByUser(parsed.data.fileKey, req.user!.sub);

  if (parsed.data.vehicleId) {
    const vehicle = await prisma.vehicle.findFirst({ where: { id: parsed.data.vehicleId, driverId: driver.id } });
    if (!vehicle) throw Errors.notFound("Vehicle");
  }

  const doc = await prisma.driverDocument.create({
    data: {
      driverId: driver.id,
      vehicleId: parsed.data.vehicleId,
      title: parsed.data.title,
      documentType: parsed.data.documentType,
      fileKey: parsed.data.fileKey,
      expiryDate,
      status: "PENDING",
    },
  });
  res.status(201).json(doc);
}));

const resubmitSchema = z.object({ fileKey: z.string().min(1) });

// Driver: replace a rejected document's file and send it back for review.
// Reuses the same row (no orphan duplicate) — only the fileKey and status
// change; title/documentType/vehicleId association are preserved.
documentsRouter.post("/documents/:id/resubmit", requireAuth, requireRole("Driver"), asyncHandler(async (req, res) => {
  const parsed = resubmitSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) throw Errors.notFound("Driver profile");

  const doc = await prisma.driverDocument.findFirst({ where: { id: req.params.id, driverId: driver.id } });
  if (!doc) throw Errors.notFound("Document");

  if (doc.status !== "REJECTED") {
    throw Errors.conflict("Only a rejected document can be resubmitted.");
  }

  assertFileKeyOwnedByUser(parsed.data.fileKey, req.user!.sub);

  const updated = await prisma.driverDocument.update({
    where: { id: doc.id },
    data: {
      fileKey: parsed.data.fileKey,
      status: "PENDING",
      rejectionReason: null,
      reviewedAt: null,
      reviewedById: null,
    },
  });
  res.json(updated);
}));

// Driver (own) or Admin (any): a short-lived signed URL to view a document's
// actual file. The documents bucket blocks all public access (see
// infra/lib/storage-stack.ts) — this is the only sanctioned way to read one
// back, and it never hands out a durable/public link.
documentsRouter.get("/documents/:id/view", requireAuth, asyncHandler(async (req, res) => {
  const doc = await prisma.driverDocument.findUnique({
    where: { id: req.params.id },
    include: { driver: { include: { user: true } } },
  });
  if (!doc) throw Errors.notFound("Document");

  const isOwner = doc.driver.user.cognitoSub === req.user!.sub;
  const isAdmin = req.user!.groups.includes("Admin");
  if (!isOwner && !isAdmin) {
    throw Errors.authorization("Not authorized to view this document");
  }

  if (!doc.fileKey) throw Errors.notFound("No file uploaded for this document yet");
  if (!env.DOCUMENTS_BUCKET) throw Errors.internalServerError("Documents bucket is not configured");

  const command = new GetObjectCommand({ Bucket: env.DOCUMENTS_BUCKET, Key: doc.fileKey });
  const viewUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
  res.json({ viewUrl, expiresIn: 300 });
}));

const reviewSchema = z.object({
  status: z.enum(["APPROVED", "REJECTED"]),
  // Mandatory on REJECTED (checked below, not by zod, so the error message
  // names the real cause instead of a generic schema error).
  rejectionReason: z.string().min(1).optional(),
});

// Admin: approve/reject a document. Rejecting without a reason is rejected
// itself — a driver must never see a bare "Rejected" with no explanation.
documentsRouter.patch("/documents/:id/review", requireAuth, requireRole("Admin"), asyncHandler(async (req, res) => {
  const parsed = reviewSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  if (parsed.data.status === "REJECTED" && !parsed.data.rejectionReason) {
    return res.status(400).json({ error: "A rejection reason is required." });
  }

  const adminUser = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!adminUser) throw Errors.notFound("Admin user");

  const doc = await prisma.driverDocument.update({
    where: { id: req.params.id },
    data: {
      status: parsed.data.status,
      rejectionReason: parsed.data.status === "REJECTED" ? parsed.data.rejectionReason : null,
      reviewedAt: new Date(),
      reviewedById: adminUser.id,
    },
  });
  res.json(doc);
}));
