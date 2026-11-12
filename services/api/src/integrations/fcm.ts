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
        batch.map((m) => ({
          token: m.token,
          notification: { title: m.title, body: m.body },
          data: { link: m.link, ...(m.campaignId ? { campaignId: m.campaignId } : {}) },
          android: { priority: 'normal', notification: { channelId: 'offers' } },
          apns: { payload: { aps: { sound: 'default', 'thread-id': 'yaqeen-updates' } } },
        })),
      );
      res.responses.forEach((r, idx) => {
        if (r.success) ok++;
        else if (r.error?.code === 'messaging/registration-token-not-registered') invalidTokens.push(batch[idx]!.token);
      });
    }
    return { ok, invalidTokens };
  }
}
