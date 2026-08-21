import { CognitoJwtVerifier } from "aws-jwt-verify";
import type { NextFunction, Request, Response } from "express";
import { env } from "../config/env";
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
    return res.status(401).json({ error: "Missing bearer token" });
  }

  let payload;
  try {
    const token = header.slice("Bearer ".length);
    payload = await verifier.verify(token);
  } catch {
    return res.status(401).json({ error: "Invalid or expired token" });
  }

  const groups = Array.isArray(payload["cognito:groups"]) ? (payload["cognito:groups"] as string[]) : [];

  // Enforced once, here, for every authenticated request — the one place
  // all protected routes already pass through — rather than in each route.
  // Admins are exempt so a suspended Admin account can still perform the
  // recovery actions (e.g. un-suspending other users) that only an Admin
  // can do. A caller with no User row yet (first call after Cognito
  // sign-up, before POST /riders/me or /drivers/me has run) isn't blocked;
  // suspension only applies once a profile actually exists.
  if (!groups.includes("Admin")) {
    const user = await prisma.user.findUnique({
      where: { cognitoSub: payload.sub },
      select: { suspended: true },
    });
    if (user?.suspended) {
      return res.status(403).json({ error: "Account suspended" });
    }
  }

  req.user = {
    sub: payload.sub,
    email: typeof payload.email === "string" ? payload.email : undefined,
    groups,
  };
  next();
}

export function requireRole(...allowed: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const groups = req.user?.groups ?? [];
    if (!allowed.some((role) => groups.includes(role))) {
      return res.status(403).json({ error: "Insufficient permissions" });
    }
    next();
  };
}
