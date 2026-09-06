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
  | "cash:write";

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
  ]),
  OPERATIONS_MANAGER: new Set(["pricing:write", "drivers:write"]),
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
    const role = await effectiveAdminRole(req.user!.sub);
    if (!ADMIN_PERMISSIONS[role].has(permission)) {
      logSecurityEvent("AUTHZ_FAILURE", req, { required: `admin:${permission}`, adminRole: role });
      return res.status(403).json({ error: "Your admin role doesn't permit this action" });
    }
    next();
  };
}
