import { Router } from "express";
import { z } from "zod";
import type { AdminRole } from "@prisma/client";
import { UsernameExistsException } from "@aws-sdk/client-cognito-identity-provider";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { requireAdminPermission } from "../lib/admin-permissions";
import { cognitoGroups } from "../services/cognito";
import { recordAudit } from "../lib/audit";
import { sensitiveLimiter } from "../middleware/rate-limit";

export const adminUsersRouter = Router();

const ADMIN_ROLES = ["SUPER_ADMIN", "OPERATIONS_MANAGER", "SUPPORT_AGENT", "FINANCE_VIEWER"] as const;

function isEffectiveSuperAdmin(adminRole: AdminRole | null): boolean {
  return adminRole === null || adminRole === "SUPER_ADMIN";
}

type AdminUserRow = {
  id: string;
  firstName: string;
  lastName: string;
  email: string;
  adminRole: AdminRole | null;
  suspended: boolean;
  createdAt: Date;
  lastLoginAt: Date | null;
  cognitoSub: string;
};

/**
 * The Admin Users list/detail shape. Account status and MFA status are never
 * stored in Postgres — both are read live from Cognito (see
 * cognitoGroups.adminUserStatus) so this can never show a value that has
 * drifted from the real account state. "Invited" means Cognito's
 * FORCE_CHANGE_PASSWORD status: the temporary password was emailed but the
 * admin hasn't signed in and set their own password yet.
 */
async function serializeAdminUser(u: AdminUserRow) {
  const cognitoStatus = await cognitoGroups.adminUserStatus(u.cognitoSub);
  const status = u.suspended
    ? "SUSPENDED"
    : cognitoStatus == null
      ? "UNKNOWN"
      : cognitoStatus.cognitoStatus === "FORCE_CHANGE_PASSWORD"
        ? "INVITED"
        : "ACTIVE";
  return {
    id: u.id,
    name: `${u.firstName} ${u.lastName}`.trim(),
    email: u.email,
    adminRole: u.adminRole ?? "SUPER_ADMIN",
    suspended: u.suspended,
    status,
    mfaEnabled: cognitoStatus?.mfaEnabled ?? false,
    createdAt: u.createdAt,
    lastLoginAt: u.lastLoginAt,
  };
}

async function findAdminById(id: string) {
  const target = await prisma.user.findUnique({ where: { id } });
  if (!target || target.role !== "ADMIN") return null;
  return target;
}

// Super Admin: list every admin-group user and their preset.
adminUsersRouter.get("/admin-users", requireAuth, requireAdminPermission("manage_admins"), async (_req, res) => {
  const users = await prisma.user.findMany({ where: { role: "ADMIN" }, orderBy: { createdAt: "desc" } });
  res.json(await Promise.all(users.map(serializeAdminUser)));
});

// Any authenticated admin: their own profile, for the Admin App's profile
// screen. Deliberately only requireRole("Admin") (the base Cognito-group
// check), not requireAdminPermission("manage_admins") — every admin can see
// their own profile regardless of preset, same as any other app's "my
// account" page.
adminUsersRouter.get("/admin-users/me", requireAuth, requireRole("Admin"), async (req, res) => {
  const me = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!me) {
    // A Cognito "Admin"-group member with no Postgres User row at all — the
    // same legacy shape effectiveAdminRole() treats as full access (see
    // lib/admin-permissions.ts). Profile data falls back to the verified
    // token claims since there's no User row to read from.
    const cognitoStatus = await cognitoGroups.adminUserStatus(req.user!.sub);
    return res.json({
      id: null,
      name: req.user!.email ?? "",
      email: req.user!.email ?? "",
      adminRole: "SUPER_ADMIN",
      suspended: false,
      status: "ACTIVE",
      mfaEnabled: cognitoStatus?.mfaEnabled ?? false,
      createdAt: null,
      lastLoginAt: null,
    });
  }
  res.json(await serializeAdminUser(me));
});

// Self-service: record that the calling admin just finished TOTP enrollment.
// The enrollment itself (AssociateSoftwareToken/VerifySoftwareToken/
// SetUserMFAPreference) happens directly between the Admin App and Cognito —
// this call exists purely to complete the audit trail with an
// ADMIN_USER_MFA_ENABLED entry; Cognito remains the actual source of truth
// for whether MFA is enabled (see serializeAdminUser).
adminUsersRouter.post("/admin-users/me/mfa-enrolled", requireAuth, requireRole("Admin"), async (req, res) => {
  const me = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  void recordAudit({
    actorSub: req.user!.sub,
    action: "ADMIN_USER_MFA_ENABLED",
    entityType: "User",
    entityId: me?.id ?? req.user!.sub,
    metadata: {},
  });
  res.status(204).send();
});

// Super Admin: view a single admin's detail.
adminUsersRouter.get("/admin-users/:id", requireAuth, requireAdminPermission("manage_admins"), async (req, res) => {
  const target = await findAdminById(req.params.id);
  if (!target) return res.status(404).json({ error: "Admin user not found" });
  res.json(await serializeAdminUser(target));
});

const createAdminUserSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  firstName: z.string().trim().min(1),
  lastName: z.string().trim().min(1),
  adminRole: z.enum(ADMIN_ROLES),
});

// Super Admin: invite a new admin user. Cognito emails them a temporary
// password (Cognito's default invitation template) — nothing here ever
// handles or displays a password. Rate-limited: each invite creates a real
// Cognito account and sends a real email.
adminUsersRouter.post(
  "/admin-users",
  requireAuth,
  requireAdminPermission("manage_admins"),
  sensitiveLimiter,
  async (req, res) => {
    const parsed = createAdminUserSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
    const { email, firstName, lastName, adminRole } = parsed.data;

    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) return res.status(409).json({ error: "A user with this email already exists" });

    let sub: string;
    try {
      ({ sub } = await cognitoGroups.createAdminUser({ email, firstName, lastName }));
    } catch (err) {
      // A Cognito account with this email already exists even though our own
      // Postgres row doesn't (e.g. a previous invite that failed after the
      // Cognito call but before the User row was written) — a clear 409
      // instead of a raw 500.
      if (err instanceof UsernameExistsException) {
        return res.status(409).json({ error: "A Cognito account with this email already exists" });
      }
      throw err;
    }
    await cognitoGroups.addUserToGroup(sub, "Admin");

    const created = await prisma.user.create({
      data: { cognitoSub: sub, role: "ADMIN", firstName, lastName, email, adminRole },
    });
    void recordAudit({
      actorSub: req.user!.sub,
      action: "ADMIN_USER_CREATED",
      entityType: "User",
      entityId: created.id,
      metadata: { email, adminRole, invitationSent: true },
    });
    res.status(201).json(await serializeAdminUser(created));
  },
);

// Super Admin: re-send the invitation email for an admin who hasn't
// completed their first sign-in yet. Rejected once the admin has actually
// set a password (Cognito's own RESEND rule) — surfaced as a clear 409
// rather than the raw Cognito error.
adminUsersRouter.post(
  "/admin-users/:id/resend-invitation",
  requireAuth,
  requireAdminPermission("manage_admins"),
  sensitiveLimiter,
  async (req, res) => {
    const target = await findAdminById(req.params.id);
    if (!target) return res.status(404).json({ error: "Admin user not found" });

    const cognitoStatus = await cognitoGroups.adminUserStatus(target.cognitoSub);
    if (cognitoStatus?.cognitoStatus !== "FORCE_CHANGE_PASSWORD") {
      return res.status(409).json({ error: "This admin has already signed in and set a password" });
    }

    await cognitoGroups.resendAdminInvitation({
      email: target.email,
      firstName: target.firstName,
      lastName: target.lastName,
    });
    void recordAudit({
      actorSub: req.user!.sub,
      action: "ADMIN_USER_INVITATION_RESENT",
      entityType: "User",
      entityId: target.id,
      metadata: { email: target.email },
    });
    res.json(await serializeAdminUser(target));
  },
);

// Super Admin: force a password reset for another admin (e.g. suspected
// compromise, or they're locked out and can't use "Forgot password?"
// themselves). Identical underlying Cognito flow to self-service forgot
// password — this never returns, stores, or logs a password or reset code.
adminUsersRouter.post(
  "/admin-users/:id/password-reset",
  requireAuth,
  requireAdminPermission("manage_admins"),
  sensitiveLimiter,
  async (req, res) => {
    const target = await findAdminById(req.params.id);
    if (!target) return res.status(404).json({ error: "Admin user not found" });

    await cognitoGroups.adminResetUserPassword(target.cognitoSub);
    void recordAudit({
      actorSub: req.user!.sub,
      action: "ADMIN_USER_PASSWORD_RESET_REQUESTED",
      entityType: "User",
      entityId: target.id,
      metadata: {},
    });
    res.json(await serializeAdminUser(target));
  },
);

const changeRoleSchema = z.object({ adminRole: z.enum(ADMIN_ROLES) });

// Super Admin: change an admin's preset. Blocked if it would leave zero
// Super Admins — otherwise a lone Super Admin could lock everyone out of
// admin-user management, including themselves, with no way back in short of
// a direct database edit.
adminUsersRouter.patch("/admin-users/:id/role", requireAuth, requireAdminPermission("manage_admins"), async (req, res) => {
  const parsed = changeRoleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const target = await findAdminById(req.params.id);
  if (!target) return res.status(404).json({ error: "Admin user not found" });

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
  res.json(await serializeAdminUser(updated));
});

const changeStatusSchema = z.object({ suspended: z.boolean() });

// Super Admin: suspend/reinstate an admin account. Suspending also disables
// the Cognito account outright (not just a Postgres flag) so a suspended
// admin can't obtain a new token, mirroring an IAM access-key deactivation.
// Blocked if it would leave zero active Super Admins, and an admin can never
// suspend their own account (accidental self-lockout) — even a Super Admin
// with peers remaining must have someone else do it.
adminUsersRouter.patch("/admin-users/:id/status", requireAuth, requireAdminPermission("manage_admins"), async (req, res) => {
  const parsed = changeStatusSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const target = await findAdminById(req.params.id);
  if (!target) return res.status(404).json({ error: "Admin user not found" });

  if (target.cognitoSub === req.user!.sub) {
    return res.status(400).json({ error: "You cannot change your own account status" });
  }

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
  if (parsed.data.suspended) {
    // Disabling blocks *new* sign-ins, but a refresh token issued before this
    // moment would otherwise keep minting fresh access tokens for up to its
    // full 30-day lifetime — revoke it outright so suspension actually ends
    // the admin's live session, not just future ones (audit Finding T2).
    await cognitoGroups.globalSignOut(target.cognitoSub);
  }
  void recordAudit({
    actorSub: req.user!.sub,
    action: parsed.data.suspended ? "ADMIN_USER_DISABLED" : "ADMIN_USER_ENABLED",
    entityType: "User",
    entityId: updated.id,
    metadata: {},
  });
  res.json(await serializeAdminUser(updated));
});
