import { Router } from "express";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const notificationsRouter = Router();

async function findOwnUser(cognitoSub: string) {
  return prisma.user.findUnique({ where: { cognitoSub } });
}

// Caller: my own notifications, newest first. Every row is scoped to the
// authenticated user's own id — there is no way to pass another user's id in,
// so this can never leak another customer's notifications.
notificationsRouter.get("/notifications", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const where = { userId: user.id };
  const [notifications, total, unreadCount] = await Promise.all([
    prisma.notification.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.notification.count({ where }),
    prisma.notification.count({ where: { ...where, read: false } }),
  ]);
  res.json({ ...paginate(notifications, total, page, pageSize), unreadCount });
});

// Caller: mark one of my own notifications as read. 404s (not 403) for a
// notification that exists but belongs to someone else, so the response
// can't be used to enumerate other users' notification ids.
notificationsRouter.patch("/notifications/:id/read", requireAuth, async (req, res) => {
  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const existing = await prisma.notification.findUnique({ where: { id: req.params.id } });
  if (!existing || existing.userId !== user.id) {
    return res.status(404).json({ error: "Notification not found" });
  }

  const notification = await prisma.notification.update({
    where: { id: existing.id },
    data: { read: true },
  });
  res.json(notification);
});

// Caller: mark all of my own notifications as read.
notificationsRouter.post("/notifications/read-all", requireAuth, async (req, res) => {
  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const result = await prisma.notification.updateMany({
    where: { userId: user.id, read: false },
    data: { read: true },
  });
  res.json({ updated: result.count });
});
