/**
 * Serve a stored recording with byte-range support (Safari and iOS players refuse audio without 206
 * responses) and an ETag. Recordings are small (≤ 200 KB) and held in memory.
 */
import { createHash } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { RECORDING_FORMAT } from '@yaqeen/contracts';

export function sendAudio(req: FastifyRequest, reply: FastifyReply, audio: Buffer, cacheControl: string) {
  const etag = `"${createHash('sha256').update(audio).digest('base64url').slice(0, 27)}"`;
  reply.header('ETag', etag);
  reply.header('Accept-Ranges', 'bytes');
  reply.header('Cache-Control', cacheControl);
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.type(RECORDING_FORMAT.mimes[0]);
  if (req.headers['if-none-match'] === etag) return reply.code(304).send();
  const range = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range ?? '').trim());
  if (range && (range[1] || range[2])) {
    const size = audio.length;
    let start: number;
    let end: number;
    if (range[1] === '') {
      start = Math.max(0, size - Number(range[2]));
      end = size - 1;
    } else {
      start = Number(range[1]);
      end = range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
    }
    if (start >= size || start > end) {
      reply.header('Content-Range', `bytes */${size}`);
      return reply.code(416).send();
    }
    reply.header('Content-Range', `bytes ${start}-${end}/${size}`);
    return reply.code(206).send(audio.subarray(start, end + 1));
  }
  return reply.code(200).send(audio);
}
