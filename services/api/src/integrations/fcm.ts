/**
 * Firebase Cloud Messaging sender (remote pushes: campaigns, reward/challenge nudges).
 * Prayer and azkar reminders are LOCAL notifications scheduled on the device — not sent here.
 */
import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  /** Deep link handled by the app router, e.g. "yaqeen://challenge". */
  link: string;
  campaignId?: string;
  /** Campaign kind — picks the Android channel and the Yaqeen sound. Defaults to offers. */
  kind?: 'challenge' | 'rewards' | 'offers';
}

/**
 * Channel + sound for a push. The app creates the `challenge` and `offers` Android channels with
 * these sounds (apps/mobile NotificationSound); on iOS the `.caf` ships in the app bundle.
 * Challenge and reward nudges glint (yq_challenge); store offers are the quiet pebble (yq_offers).
 */
export function pushSound(kind: PushMessage['kind']): { channelId: 'challenge' | 'offers'; sound: string } {
  return kind === 'challenge' || kind === 'rewards'
    ? { channelId: 'challenge', sound: 'yq_challenge' }
    : { channelId: 'offers', sound: 'yq_offers' };
}

export interface PushResult {
  ok: number;
  invalidTokens: string[];
}

export class FcmSender {
  private app: App | null = null;

  constructor(serviceAccountJson: string) {
    if (!serviceAccountJson) return;
    this.app =
      getApps()[0] ?? initializeApp({ credential: cert(JSON.parse(serviceAccountJson) as Record<string, string>) });
  }

  get configured(): boolean {
    return this.app !== null;
  }

  async sendMany(messages: PushMessage[]): Promise<PushResult> {
    if (!this.app || messages.length === 0) return { ok: 0, invalidTokens: [] };
    const messaging = getMessaging(this.app);
    const invalidTokens: string[] = [];
    let ok = 0;
    for (let i = 0; i < messages.length; i += 500) {
      const batch = messages.slice(i, i + 500);
      const res = await messaging.sendEach(
        batch.map((m) => {
          const { channelId, sound } = pushSound(m.kind);
          return {
            token: m.token,
            notification: { title: m.title, body: m.body },
            data: { link: m.link, ...(m.campaignId ? { campaignId: m.campaignId } : {}) },
            android: { priority: 'normal' as const, notification: { channelId, sound } },
            apns: { payload: { aps: { sound: `${sound}.caf`, 'thread-id': 'yaqeen-updates' } } },
          };
        }),
      );
      res.responses.forEach((r, idx) => {
        if (r.success) ok++;
        else if (r.error?.code === 'messaging/registration-token-not-registered') invalidTokens.push(batch[idx]!.token);
      });
    }
    return { ok, invalidTokens };
  }
}
