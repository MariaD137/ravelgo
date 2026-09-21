import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { requireActiveAdmin, requireAdminPermission } from "../lib/admin-permissions";
import { containsInsensitive, paginate, paginationQuerySchema, searchQuerySchema } from "../lib/pagination";
import type { Prisma } from "@prisma/client";

export const supportRouter = Router();

const createTicketSchema = z.object({
  subject: z.string().min(1),
  category: z.string().min(1),
});

// Rider or Driver: open a support ticket
supportRouter.post("/support-tickets", requireAuth, async (req, res) => {
  const parsed = createTicketSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const ticket = await prisma.supportTicket.create({
    data: { ...parsed.data, userId: user.id },
  });
  res.status(201).json(ticket);
});

// Caller: view my own tickets
supportRouter.get("/support-tickets/mine", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const tickets = await prisma.supportTicket.findMany({
    where: { userId: user.id },
    orderBy: { createdAt: "desc" },
  });
  res.json(tickets);
});

// Admin: list all support tickets, optionally narrowed by a ?q= search
// against the subject, category, or the raising user's name/email.
supportRouter.get("/support-tickets", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = paginationQuerySchema.merge(searchQuerySchema).safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize, q } = parsed.data;
  const where: Prisma.SupportTicketWhereInput = q
    ? {
        OR: [
          { subject: containsInsensitive(q) },
          { category: containsInsensitive(q) },
          { user: { firstName: containsInsensitive(q) } },
          { user: { lastName: containsInsensitive(q) } },
          { user: { email: containsInsensitive(q) } },
        ],
      }
    : {};

  const [tickets, total] = await Promise.all([
    prisma.supportTicket.findMany({
      where,
      include: { user: true },
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.supportTicket.count({ where }),
  ]);
  res.json(paginate(tickets, total, page, pageSize));
});

const statusSchema = z.object({ status: z.enum(["OPEN", "IN_PROGRESS", "RESOLVED"]) });

// Admin: update ticket status
supportRouter.patch("/support-tickets/:id/status", requireAuth, requireAdminPermission("alerts:write"), async (req, res) => {
  const parsed = statusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const ticket = await prisma.supportTicket.update({
    where: { id: req.params.id },
    data: { status: parsed.data.status },
  });
  res.json(ticket);
});
