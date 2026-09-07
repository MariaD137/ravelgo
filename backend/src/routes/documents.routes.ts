import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";

export const documentsRouter = Router();

// Driver: view my own documents
documentsRouter.get("/documents/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const documents = await prisma.driverDocument.findMany({ where: { driverId: driver.id } });
  res.json(documents);
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

  const driver = await prisma.driver.findFirst({ where: { user: { cognitoSub: req.user!.sub } } });
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
