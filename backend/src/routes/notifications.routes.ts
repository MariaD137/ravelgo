import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";
import { env } from "../config/env";

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

const registerDeviceTokenSchema = z.object({
  token: z.string().min(1).max(4096),
  platform: z.enum(["IOS", "ANDROID"]),
});

// Caller: register (or re-register) a device token for push delivery.
// Ownership always comes from the authenticated Cognito identity — there is
// no field in the request body a client could use to register a token
// against a different user. A token is unique platform-wide (the OS can
// hand the same token to a different install later), so re-registering an
// already-known token simply reassigns it to whoever registers it now,
// rather than erroring as a duplicate.
notificationsRouter.post("/notifications/device-tokens", requireAuth, async (req, res) => {
  const parsed = registerDeviceTokenSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const { token, platform } = parsed.data;
  // Pinpoint sends directly to the raw token (see services/push.ts) — no
  // separate "endpoint" resource to pre-create, so registering is just this
  // upsert. Re-registering an already-known token reassigns it to whoever
  // registers it now rather than erroring.
  const pushToken = await prisma.pushToken.upsert({
    where: { token },
    create: { userId: user.id, token, platform },
    update: { userId: user.id, platform },
  });
  res.status(201).json({
    id: pushToken.id,
    platform: pushToken.platform,
    // Tells the app whether push is actually wired up server-side (a
    // Pinpoint application configured) without exposing any AWS identifier.
    registered: env.PINPOINT_APPLICATION_ID != null,
  });
});

const unregisterDeviceTokenSchema = z.object({ token: z.string().min(1).max(4096) });

// Caller: unregister my own device token (e.g. on logout). 404s (not 403)
// for a token that exists but belongs to someone else, same reasoning as
// the notification-read route above.
notificationsRouter.delete("/notifications/device-tokens", requireAuth, async (req, res) => {
  const parsed = unregisterDeviceTokenSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const user = await findOwnUser(req.user!.sub);
  if (!user) return res.status(404).json({ error: "User profile not found" });

  const existing = await prisma.pushToken.findUnique({ where: { token: parsed.data.token } });
  if (!existing || existing.userId !== user.id) {
    return res.status(404).json({ error: "Device token not found" });
  }

  await prisma.pushToken.delete({ where: { id: existing.id } });
  res.status(204).send();
});
