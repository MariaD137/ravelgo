import { Router } from "express";
import { z } from "zod";
import type { AdminRole } from "@prisma/client";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { cognitoGroups } from "../services/cognito";
import { recordAudit } from "../lib/audit";

export const adminUsersRouter = Router();

const ADMIN_ROLES = ["SUPER_ADMIN", "OPERATIONS_MANAGER", "SUPPORT_AGENT", "FINANCE_VIEWER"] as const;

function isEffectiveSuperAdmin(adminRole: AdminRole | null): boolean {
  return adminRole === null || adminRole === "SUPER_ADMIN";
}

function publicAdminUser(u: {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  adminRole: AdminRole | null;
  suspended: boolean;
  createdAt: Date;
}) {
  return {
    id: u.id,
    name: `${u.firstName} ${u.lastName}`.trim(),
    email: u.email,
    adminRole: u.adminRole ?? "SUPER_ADMIN",
    suspended: u.suspended,
    createdAt: u.createdAt,
  };
}

// Super Admin: list every admin-group user and their preset.
adminUsersRouter.get("/admin-users", requireAuth, requireAdminPermission("manage_admins"), async (_req, res) => {
  const users = await prisma.user.findMany({ where: { role: "ADMIN" }, orderBy: { createdAt: "desc" } });
  res.json(users.map(publicAdminUser));
});

const createAdminUserSchema = z.object({
  email: z.string().email(),
  firstName: z.string().min(1),
  lastName: z.string().min(1),
  adminRole: z.enum(ADMIN_ROLES),
});

// Super Admin: invite a new admin user. Cognito emails them a temporary
// password (Cognito's default invitation template) — nothing here ever
// handles or displays a password.
adminUsersRouter.post("/admin-users", requireAuth, requireAdminPermission("manage_admins"), async (req, res) => {
  const parsed = createAdminUserSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { email, firstName, lastName, adminRole } = parsed.data;

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) return res.status(409).json({ error: "A user with this email already exists" });

  const { username } = await cognitoGroups.createAdminUser({ email, firstName, lastName });
  await cognitoGroups.addUserToGroup(username, "Admin");

  const created = await prisma.user.create({
    data: { cognitoSub: username, role: "ADMIN", firstName, lastName, email, adminRole },
  });
  void recordAudit({
    actorSub: req.user!.sub,
    action: "ADMIN_USER_CREATED",
    entityType: "User",
    entityId: created.id,
    metadata: { email, adminRole },
  });
  res.status(201).json(publicAdminUser(created));
});

const changeRoleSchema = z.object({ adminRole: z.enum(ADMIN_ROLES) });

// Super Admin: change an admin's preset. Blocked if it would leave zero
// Super Admins — otherwise a lone Super Admin could lock everyone out of
// admin-user management, including themselves, with no way back in short of
// a direct database edit.
adminUsersRouter.patch("/admin-users/:id/role", requireAuth, requireAdminPermission("manage_admins"), async (req, res) => {
  const parsed = changeRoleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const target = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!target || target.role !== "ADMIN") return res.status(404).json({ error: "Admin user not found" });

  if (isEffectiveSuperAdmin(target.adminRole) && parsed.data.adminRole !== "SUPER_ADMIN") {
    const superAdminCount = await prisma.user.count({
      where: { role: "ADMIN", OR: [{ adminRole: "SUPER_ADMIN" }, { adminRole: null }] },
    });
    if (superAdminCount <= 1) {
      return res.status(409).json({ error: "At least one Super Admin must remain" });
    }
  }

  const updated = await prisma.user.update({ where: { id: target.id }, data: { adminRole: parsed.data.adminRole } });
  void recordAudit({
    actorSub: req.user!.sub,
    action: "ADMIN_USER_ROLE_CHANGED",
    entityType: "User",
    entityId: updated.id,
    metadata: { adminRole: parsed.data.adminRole },
  });
  res.json(publicAdminUser(updated));
});

const changeStatusSchema = z.object({ suspended: z.boolean() });

// Super Admin: suspend/reinstate an admin account. Suspending also disables
// the Cognito account outright (not just a Postgres flag) so a suspended
// admin can't obtain a new token, mirroring an IAM access-key deactivation.
// Blocked if it would leave zero active Super Admins.
adminUsersRouter.patch("/admin-users/:id/status", requireAuth, requireAdminPermission("manage_admins"), async (req, res) => {
  const parsed = changeStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const target = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!target || target.role !== "ADMIN") return res.status(404).json({ error: "Admin user not found" });

  if (parsed.data.suspended && !target.suspended && isEffectiveSuperAdmin(target.adminRole)) {
    const activeSuperAdmins = await prisma.user.count({
      where: { role: "ADMIN", suspended: false, OR: [{ adminRole: "SUPER_ADMIN" }, { adminRole: null }] },
    });
    if (activeSuperAdmins <= 1) {
      return res.status(409).json({ error: "At least one active Super Admin must remain" });
    }
  }

  const updated = await prisma.user.update({ where: { id: target.id }, data: { suspended: parsed.data.suspended } });
  await cognitoGroups.setUserEnabled(target.cognitoSub, !parsed.data.suspended);
  void recordAudit({
    actorSub: req.user!.sub,
    action: "ADMIN_USER_STATUS_CHANGED",
    entityType: "User",
    entityId: updated.id,
    metadata: { suspended: parsed.data.suspended },
  });
  res.json(publicAdminUser(updated));
});
