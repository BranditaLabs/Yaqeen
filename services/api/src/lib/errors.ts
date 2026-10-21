import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError, z } from 'zod';

/** Typed application error → `{ error: { code, message } }` with the given HTTP status. */
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message?: string,
    public readonly details?: unknown,
  ) {
    super(message ?? code);
  }
}

export const notFound = (what = 'resource') => new AppError(404, 'not_found', `${what} not found`);
export const forbidden = (code = 'forbidden', msg?: string) => new AppError(403, code, msg);
export const unauthorized = (msg = 'unauthorized') => new AppError(401, 'unauthorized', msg);
export const conflict = (code: string, msg?: string) => new AppError(409, code, msg);
export const badRequest = (code: string, msg?: string, details?: unknown) => new AppError(400, code, msg, details);

export function errorHandler(err: FastifyError | Error, req: FastifyRequest, reply: FastifyReply) {
  if (err instanceof AppError) {
    return reply.status(err.status).send({ error: { code: err.code, message: err.message, details: err.details } });
  }
  if (err instanceof ZodError) {
    return reply
      .status(400)
      .send({ error: { code: 'validation_failed', message: z.prettifyError(err), details: err.issues } });
  }
  const fe = err as FastifyError;
  if (fe.statusCode && fe.statusCode < 500) {
    return reply.status(fe.statusCode).send({ error: { code: fe.code ?? 'bad_request', message: fe.message } });
  }
  req.log.error({ err }, 'unhandled error');
  return reply.status(500).send({ error: { code: 'internal', message: 'Something went wrong' } });
}
