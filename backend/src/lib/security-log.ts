import type { Request } from "express";

/**
 * Emits a single, stable, machine-parseable line for security-relevant
 * events. CloudWatch metric filters in infra/lib/monitoring-stack.ts match on
 * the `SECURITY_EVENT <TYPE>` prefix to turn these into metrics and alarms, so
 * the token names here are a contract with that stack — don't rename one
 * without updating the other.
 *
 * Deliberately logs NO token, password, card number, or request body — only
 * the event type, the path, the method, and the caller's Cognito sub when a
 * verified identity is already on the request. Enough to investigate an
 * attack, nothing that would itself be sensitive in a log.
 */
export type SecurityEventType =
  | "AUTH_FAILURE" // 401: missing / invalid / expired token
  | "AUTHZ_FAILURE" // 403: authenticated but wrong role/ownership
  | "RATE_LIMIT_EXCEEDED" // 429
  | "PAYMENT_FAILURE"; // a charge/refund could not be completed

export function logSecurityEvent(type: SecurityEventType, req: Request, extra?: Record<string, string>): void {
  const parts: Record<string, string> = {
    method: req.method,
    path: req.path,
  };
  // req.user is added by the auth middleware's global augmentation; read it
  // defensively so this module doesn't depend on that augmentation being in
  // scope (it isn't under per-file test transpilation).
  const sub = (req as Request & { user?: { sub?: string } }).user?.sub;
  if (sub) parts.sub = sub;
  if (extra) Object.assign(parts, extra);

  const detail = Object.entries(parts)
    .map(([k, v]) => `${k}=${v}`)
    .join(" ");
  // Single line, stable prefix — see the metric filters in monitoring-stack.ts.
  console.warn(`SECURITY_EVENT ${type} ${detail}`);
}
