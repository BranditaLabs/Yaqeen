import { describe, expect, it } from 'vitest';
import { pushSound } from '../src/integrations/fcm.js';

describe('pushSound', () => {
  it('challenge and reward nudges use the challenge channel and the glint', () => {
    expect(pushSound('challenge')).toEqual({ channelId: 'challenge', sound: 'yq_challenge' });
    expect(pushSound('rewards')).toEqual({ channelId: 'challenge', sound: 'yq_challenge' });
  });
  it('offers and unspecified pushes stay in the quiet offers channel', () => {
    expect(pushSound('offers')).toEqual({ channelId: 'offers', sound: 'yq_offers' });
    expect(pushSound(undefined)).toEqual({ channelId: 'offers', sound: 'yq_offers' });
  });
});
