/**
 * The opt-in community for the app (APP_SPEC §5.31, design §3.3), prefix /v1:
 *   GET  /leagues/current · /leagues/history                      (flag leagues)
 *   GET  /tournaments · /tournaments/:id · /tournaments/:id/standings
 *   POST /tournaments/:id/join · DELETE /tournaments/:id/join      (flag tournaments)
 *   GET  /leaderboard?scope=global|country                         (flag leaderboard)
 *   POST /community/reports · GET/POST /community/blocks · DELETE /community/blocks/:handle
 * Standings, ranks and public level rings come from the nightly snapshot only; the caller's own live
 * points appear only in fields meant for the caller. Blocks hide users both ways at read time.
 */
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { BlockRequest, LeaderboardScope, ReportRequest } from '@yaqeen/contracts';
import { userId } from '../../plugins/auth.js';
import { type CommunityFlag, requireFeature } from '../../services/community-settings.service.js';
import * as community from '../../services/community.service.js';
import * as leaderboard from '../../services/leaderboard.service.js';
import * as leagues from '../../services/leagues.service.js';
import * as tournaments from '../../services/tournaments.service.js';

const IdParam = z.object({ id: z.string() });

export const communityRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;
  app.addHook('preHandler', app.requireUser);
  const flag = (f: CommunityFlag) => async () => requireFeature(ctx, f);

  /* ---------------------------------------------------------------- leagues */
  app.get('/leagues/current', { preHandler: flag('leagues') }, async (req) => leagues.current(ctx, userId(req)));
  app.get('/leagues/history', { preHandler: flag('leagues') }, async (req) => leagues.history(ctx, userId(req)));

  /* ------------------------------------------------------------ tournaments */
  app.get('/tournaments', { preHandler: flag('tournaments') }, async (req) => tournaments.list(ctx, userId(req)));

  app.get('/tournaments/:id', { preHandler: flag('tournaments') }, async (req) => {
    const { id } = IdParam.parse(req.params);
    tournaments.assertId(id);
    return tournaments.get(ctx, userId(req), id);
  });

  app.post('/tournaments/:id/join', { preHandler: flag('tournaments'), config: { rateLimit: { max: 20, timeWindow: '1 minute' } } }, async (req) => {
    const { id } = IdParam.parse(req.params);
    tournaments.assertId(id);
    const body = z.object({ acknowledge: z.unknown().optional(), attestAdult: z.unknown().optional() }).parse(req.body ?? {});
    return tournaments.join(ctx, userId(req), id, body, req.ip);
  });

  app.delete('/tournaments/:id/join', { preHandler: flag('tournaments') }, async (req) => {
    const { id } = IdParam.parse(req.params);
    tournaments.assertId(id);
    return tournaments.leave(ctx, userId(req), id);
  });

  app.get('/tournaments/:id/standings', { preHandler: flag('tournaments') }, async (req) => {
    const { id } = IdParam.parse(req.params);
    tournaments.assertId(id);
    const { cursor } = z.object({ cursor: z.string().max(200).optional() }).parse(req.query);
    return tournaments.standings(ctx, userId(req), id, cursor);
  });

  /* ------------------------------------------------------------ leaderboard */
  app.get('/leaderboard', { preHandler: flag('leaderboard') }, async (req) => {
    const { scope } = z.object({ scope: LeaderboardScope.default('global') }).parse(req.query);
    return leaderboard.view(ctx, userId(req), scope);
  });

  /* ---------------------------------------------------------------- safety */
  app.post('/community/reports', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const body = ReportRequest.parse(req.body);
    await community.report(ctx, userId(req), body.handle, body.reason);
    return reply.status(204).send();
  });

  app.get('/community/blocks', async (req) => community.listBlocks(ctx, userId(req)));

  app.post('/community/blocks', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const { handle } = BlockRequest.parse(req.body);
    await community.block(ctx, userId(req), handle);
    return reply.status(204).send();
  });

  app.delete('/community/blocks/:handle', async (req, reply) => {
    const { handle } = z.object({ handle: z.string().min(1).max(41) }).parse(req.params);
    await community.unblock(ctx, userId(req), handle);
    return reply.status(204).send();
  });
};
