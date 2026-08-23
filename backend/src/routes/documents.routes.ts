import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { findOwnDriver } from "../services/driver";

export const documentsRouter = Router();

// Driver: view my own documents
documentsRouter.get("/documents/me", requireAuth, requireRole("Driver"), async (req, res) => {
  const driver = await findOwnDriver(req.user!.sub);
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

  // POST /uploads/presign always mints fileKey as `${callerSub}/...` — so a
  // fileKey not namespaced under the caller's own sub was never actually
  // issued to them by that endpoint. Without this check, a driver who knew
  // (or guessed) another user's sub and object key could register it as
  // their own document; this doesn't grant S3 access, but it would let a
  // driver falsely claim someone else's already-uploaded file as one of
  // their own DriverDocument rows.
  if (!parsed.data.fileKey.startsWith(`${req.user!.sub}/`)) {
    return res.status(403).json({ error: "fileKey must belong to the calling user" });
  }

  const driver = await findOwnDriver(req.user!.sub);
  if (!driver) return res.status(404).json({ error: "Driver profile not found" });

  const doc = await prisma.driverDocument.create({
    data: { driverId: driver.id, title: parsed.data.title, fileKey: parsed.data.fileKey, status: "PENDING" },
  });
  res.status(201).json(doc);
});

const reviewSchema = z.object({
  status: z.enum(["APPROVED", "REJECTED"]),
});

// Admin: approve/reject a document
documentsRouter.patch("/documents/:id/review", requireAuth, requireRole("Admin"), async (req, res) => {
  const parsed = reviewSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const doc = await prisma.driverDocument.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  res.json(doc);
});
