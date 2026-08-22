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
