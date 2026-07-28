import { CognitoJwtVerifier } from "aws-jwt-verify";
import type { NextFunction, Request, Response } from "express";
import { env } from "../config/env";

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

  try {
    const token = header.slice("Bearer ".length);
    const payload = await verifier.verify(token);
    req.user = {
      sub: payload.sub,
      email: typeof payload.email === "string" ? payload.email : undefined,
      groups: Array.isArray(payload["cognito:groups"]) ? (payload["cognito:groups"] as string[]) : [],
    };
    next();
  } catch {
    return res.status(401).json({ error: "Invalid or expired token" });
  }
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
