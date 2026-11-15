/** Cloud backup without a database: sealing, the production key rule, and the admin firewall. */
import { randomBytes } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { BACKUP_KINDS, BackupKind, BackupPutRequest, ConsentKind } from '@yaqeen/contracts';
import { loadEnv } from '../src/config/env.js';
import { isSealed, secretsKey } from '../src/lib/crypto.js';
import { open, seal } from '../src/services/backup.service.js';

describe('cloud backup', () => {
  it('seals a document with AES-256-GCM and opens it only with the same key', () => {
    const key = secretsKey(randomBytes(32).toString('base64'), 'BACKUP_SECRETS_KEY');
    const blob = seal({ notes: [{ t: 'سر' }] }, key);
    expect(isSealed(blob)).toBe(true);
    expect(blob).not.toContain('notes');
    expect(open(blob, key)).toEqual({ notes: [{ t: 'سر' }] });
    expect(() => open(blob, secretsKey(randomBytes(32).toString('base64')))).toThrow();
    expect(() => open(blob, null)).toThrow(/BACKUP_SECRETS_KEY/);
    expect(() => secretsKey(Buffer.from('short').toString('base64'), 'BACKUP_SECRETS_KEY')).toThrow(/BACKUP_SECRETS_KEY must be 32 bytes/);
  });

  it('BACKUP_SECRETS_KEY is required in production', () => {
    const prod = {
      NODE_ENV: 'production',
      JWT_SECRET: 'x'.repeat(40),
      ADMIN_JWT_SECRET: 'y'.repeat(40),
      ADMIN_SECRETS_KEY: randomBytes(32).toString('base64'),
    };
    expect(() => loadEnv(prod)).toThrow(/BACKUP_SECRETS_KEY/);
    expect(loadEnv({ ...prod, BACKUP_SECRETS_KEY: randomBytes(32).toString('base64') }).BACKUP_SECRETS_KEY).not.toBe('');
  });

  it('has a closed list of kinds and a consent of its own', () => {
    expect(ConsentKind.options).toContain('cloud_backup');
    expect(BACKUP_KINDS).toEqual(['quran_reading', 'quran_notes', 'khatma', 'hifz', 'azkar', 'listen', 'routine', 'ramadan', 'tasbeeh']);
    expect(BackupKind.safeParse('consents').success).toBe(false);
    expect(BackupPutRequest.safeParse({ baseVersion: 0, data: { a: 1 } }).success).toBe(true);
    expect(BackupPutRequest.safeParse({ baseVersion: 0, data: [1] }).success).toBe(false);
  });

  it('no admin route, analytics or conversion code can read user_backups', () => {
    const src = fileURLToPath(new URL('../src/', import.meta.url));
    const files = [
      ...readdirSync(`${src}routes/admin`).map((f) => `${src}routes/admin/${f}`),
      `${src}services/product-analytics.service.ts`,
      `${src}services/conversions.service.ts`,
      `${src}integrations/conversions.ts`,
      `${src}domain/aggregates.ts`,
    ];
    for (const f of files) {
      const code = readFileSync(f, 'utf8');
      expect(code, f).not.toMatch(/userBackups|user_backups|backup\.service/);
    }
  });
});
