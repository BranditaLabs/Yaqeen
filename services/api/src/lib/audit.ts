import type { FastifyRequest } from 'fastify';
import type { Db } from '../db/client.js';
import { auditLog } from '../db/schema.js';
import { adminOf } from '../plugins/auth.js';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

/**
 * Record an admin action. Call inside the same transaction as the change so the
 * audit row and the change commit (or roll back) together.
 */
export async function audit(
  dbOrTx: Db | Tx,
  req: FastifyRequest,
  entry: { action: string; targetType: string; targetId?: string | null; reason?: string | null; before?: unknown; after?: unknown },
) {
  const admin = adminOf(req);
  await dbOrTx.insert(auditLog).values({
    adminId: admin.sub,
    action: entry.action,
    targetType: entry.targetType,
    targetId: entry.targetId ?? null,
    reason: entry.reason ?? null,
    before: (entry.before ?? null) as never,
    after: (entry.after ?? null) as never,
    ip: req.ip,
  });
}
