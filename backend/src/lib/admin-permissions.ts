import type { NextFunction, Request, Response } from "express";
import type { AdminRole } from "@prisma/client";
import { prisma } from "../db/prisma";
import { logSecurityEvent } from "./security-log";

/**
 * Coarse, module-level permissions checked on top of the base
 * requireRole("Admin") Cognito-group gate. This intentionally only covers
 * WRITE/mutating actions across a representative cross-section of admin
 * modules (payouts, pricing, driver status, rider status, alert status, and
 * admin-user management itself) — reads stay open to any Admin-group member
 * as before. It is not a full per-endpoint IAM system; it's the fixed-role
 * preset model described to the product owner.
 */
export type AdminPermission =
  | "manage_admins"
  | "payouts:write"
  | "pricing:write"
  | "drivers:write"
  | "riders:write"
  | "alerts:write"
  // Payment-rule config (the cash limit, enabling/disabling a method) is
  // financial-configuration, not day-to-day finance ops — Super Admin only,
  // matching "Change cash limit" / "Configure commissions" in the product spec.
  | "settings:write"
  // Recording a driver's cash hand-in / reviewing reconciliation discrepancies
  // is exactly Finance's day-to-day job, so FINANCE_VIEWER gets this even
  // though it otherwise has no write permissions.
  | "cash:write"
  // Approving/rejecting a provider's listing (luxury rental, Car Paddy,
  // short-stay property) — day-to-day operations, same bucket as drivers:write.
  | "listings:write";

const ADMIN_PERMISSIONS: Record<AdminRole, ReadonlySet<AdminPermission>> = {
  SUPER_ADMIN: new Set([
    "manage_admins",
    "payouts:write",
    "pricing:write",
    "drivers:write",
    "riders:write",
    "alerts:write",
    "settings:write",
    "cash:write",
    "listings:write",
  ]),
  OPERATIONS_MANAGER: new Set(["pricing:write", "drivers:write", "listings:write"]),
  SUPPORT_AGENT: new Set(["riders:write", "alerts:write"]),
  FINANCE_VIEWER: new Set(["cash:write"]),
};

/**
 * Resolves the effective AdminRole for a caller already known to be in the
 * Cognito "Admin" group. An admin with no Postgres User row at all, or a row
 * with adminRole left null, is treated as SUPER_ADMIN — this is what keeps
 * every admin account that existed before this preset system shipped fully
 * working with no migration step required. Only an admin explicitly given a
 * restricted preset via POST/PATCH /admin-users is actually scoped down.
 */
export async function effectiveAdminRole(cognitoSub: string): Promise<AdminRole> {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  return user?.adminRole ?? "SUPER_ADMIN";
}

/**
 * Whether a caller already known to be in the Cognito "Admin" group is
 * suspended in Postgres. Suspending an admin also disables their Cognito
 * account (see PATCH /admin-users/:id/status), but AdminDisableUser only
 * blocks *issuing new* tokens — an access token issued before the suspension
 * stays cryptographically valid for up to its full hour-long lifetime (see
 * accessTokenValidity in infra/lib/auth-stack.ts). This closes that window
 * at the application layer: a suspended admin's still-live token is rejected
 * here even though Cognito itself hasn't expired it yet.
 */
export async function isSuspendedAdmin(cognitoSub: string): Promise<boolean> {
  const user = await prisma.user.findUnique({ where: { cognitoSub } });
  return user?.suspended ?? false;
}

/** Whether an AdminRole preset grants `permission`. */
export function roleHasPermission(role: AdminRole, permission: AdminPermission): boolean {
  return ADMIN_PERMISSIONS[role].has(permission);
}

/**
 * Requires the caller to be in the Cognito "Admin" group AND hold a preset
 * that grants `permission`. Must be chained after requireAuth (needs
 * req.user) — it does not itself verify the JWT.
 */
export function requireAdminPermission(permission: AdminPermission) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const groups = req.user?.groups ?? [];
    if (!groups.includes("Admin")) {
      logSecurityEvent("AUTHZ_FAILURE", req, { required: "Admin" });
      return res.status(403).json({ error: "Insufficient permissions" });
    }
    if (await isSuspendedAdmin(req.user!.sub)) {
      logSecurityEvent("AUTHZ_FAILURE", req, { required: "not_suspended" });
      return res.status(403).json({ error: "This admin account is suspended" });
    }
    const role = await effectiveAdminRole(req.user!.sub);
    if (!roleHasPermission(role, permission)) {
      logSecurityEvent("AUTHZ_FAILURE", req, { required: `admin:${permission}`, adminRole: role });
      return res.status(403).json({ error: "Your admin role doesn't permit this action" });
    }
    next();
  };
}

/**
 * Requires the caller to be in the Cognito "Admin" group AND not suspended in
 * Postgres. This is requireRole("Admin") plus the same isSuspendedAdmin check
 * requireAdminPermission already applies to writes — extended to admin READS,
 * closing the window where a just-disabled admin's still-cryptographically-
 * valid access token (issued before AdminDisableUser, cryptographically live
 * for up to its full hour-long lifetime — see accessTokenValidity in
 * infra/lib/auth-stack.ts) kept working against every admin GET endpoint,
 * including the audit log and financial dashboard, until Cognito's own token
 * expiry caught up.
 *
 * Deliberately a single drop-in replacement for requireRole("Admin") on
 * admin-only routes (same call signature, same 403 status) rather than a
 * second middleware layered on top of it, so every call site only needs to
 * swap one name and no route ends up checking suspension twice.
 *
 * Not applied to endpoints shared with non-Admin callers (e.g.
 * notifications.routes.ts's GET /notifications, read by Rider/Driver/Admin
 * alike, scoped per-user rather than role-gated at all) — gating those by
 * Admin-group membership would break them for the other two roles. A
 * suspended admin's own in-app notifications therefore remain reachable
 * through that shared endpoint; closing that specific gap would need a
 * distinct admin-only notifications view, which does not currently exist and
 * is outside this fix's scope.
 */
export function requireActiveAdmin(req: Request, res: Response, next: NextFunction) {
  const groups = req.user?.groups ?? [];
  if (!groups.includes("Admin")) {
    logSecurityEvent("AUTHZ_FAILURE", req, { required: "Admin" });
    return res.status(403).json({ error: "Insufficient permissions" });
  }
  isSuspendedAdmin(req.user!.sub)
    .then((suspended) => {
      if (suspended) {
        logSecurityEvent("AUTHZ_FAILURE", req, { required: "not_suspended" });
        return res.status(403).json({ error: "This admin account is suspended" });
      }
      next();
    })
    .catch(next);
}

/**
 * For a route shared by Driver and Admin callers (e.g. advancing a trip or
 * courier request's status) where requireAdminPermission can't sit in the
 * middleware chain without also rejecting the Driver caller: call this from
 * inside the handler, only on the branch where the caller is actually in the
 * Admin group, to enforce the same preset check requireAdminPermission would.
 * Returns true (and writes the 403) if the caller is blocked.
 */
export async function blockIfAdminLacksPermission(
  req: Request,
  res: Response,
  permission: AdminPermission,
): Promise<boolean> {
  if (await isSuspendedAdmin(req.user!.sub)) {
    logSecurityEvent("AUTHZ_FAILURE", req, { required: "not_suspended" });
    res.status(403).json({ error: "This admin account is suspended" });
    return true;
  }
  const role = await effectiveAdminRole(req.user!.sub);
  if (!roleHasPermission(role, permission)) {
    logSecurityEvent("AUTHZ_FAILURE", req, { required: `admin:${permission}`, adminRole: role });
    res.status(403).json({ error: "Your admin role doesn't permit this action" });
    return true;
  }
  return false;
}
