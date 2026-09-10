import { CognitoJwtVerifier } from "aws-jwt-verify";
import type { NextFunction, Request, Response } from "express";
import { env } from "../config/env";
import { logSecurityEvent } from "../lib/security-log";
import { prisma } from "../db/prisma";

export interface AuthenticatedUser {
  sub: string;
  email?: string;
  groups: string[];
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
    }
  }
}

export const verifier = CognitoJwtVerifier.create({
  userPoolId: env.COGNITO_USER_POOL_ID,
  tokenUse: "access",
  clientId: env.COGNITO_CLIENT_ID,
});

export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    logSecurityEvent("AUTH_FAILURE", req, { reason: "missing_token" });
    return res.status(401).json({ error: "Missing bearer token" });
  }

  try {
    const token = header.slice("Bearer ".length);
    const payload = await verifier.verify(token);
    const groups = Array.isArray(payload["cognito:groups"]) ? (payload["cognito:groups"] as string[]) : [];
    req.user = {
      sub: payload.sub,
      email: typeof payload.email === "string" ? payload.email : undefined,
      groups,
    };
    // Admin Users' "Last Login" column (see admin-users.routes.ts). There is
    // no discrete login event in this stateless-bearer-token architecture, so
    // this stamps "last seen active" on every verified admin API call —
    // fire-and-forget so it never adds latency to the request it's riding on.
    if (groups.includes("Admin")) {
      void prisma.user.updateMany({ where: { cognitoSub: payload.sub }, data: { lastLoginAt: new Date() } });
    }
    next();
  } catch {
    logSecurityEvent("AUTH_FAILURE", req, { reason: "invalid_token" });
    return res.status(401).json({ error: "Invalid or expired token" });
  }
}

export function requireRole(...allowed: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const groups = req.user?.groups ?? [];
    if (!allowed.some((role) => groups.includes(role))) {
      logSecurityEvent("AUTHZ_FAILURE", req, { required: allowed.join("|") });
      return res.status(403).json({ error: "Insufficient permissions" });
    }
    next();
  };
}
