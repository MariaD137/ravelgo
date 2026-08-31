import { prisma } from "../db/prisma";

/**
 * Record a privileged admin action in the append-only audit log.
 *
 * Best-effort: a failure to write the audit row must never fail (or roll back)
 * the action the admin actually took, so callers `void` this and it swallows
 * its own errors after logging them.
 */
export async function recordAudit(params: {
  actorSub: string;
  action: string;
  entityType: string;
  entityId?: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  try {
    await prisma.auditLog.create({
      data: {
        actorSub: params.actorSub,
        action: params.action,
        entityType: params.entityType,
        entityId: params.entityId,
        metadata: params.metadata as object | undefined,
      },
    });
  } catch (err) {
    // Never let audit logging break the primary request.
    console.error("Failed to write audit log", err);
  }
}
