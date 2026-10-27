/**
 * Seed reference data: task rules, bonus rules (disabled until approved), rewards, a first
 * super admin, and sample content in DRAFT (must pass religious review before publishing).
 *
 *   SEED_ADMIN_EMAIL=you@yaqin-brand.com SEED_ADMIN_PASSWORD='…' pnpm db:seed
 */
import { loadEnv } from '../config/env.js';
import { generateTotpSecret, hashPassword, sealSecret, secretsKey } from '../lib/crypto.js';
import { createDb } from './client.js';
import { ensureBonusRules } from '../services/program.service.js';
import { adminUsers, contentItems, contentPacks, reciters, rewards, streakMilestones, taskRules } from './schema.js';

const env = loadEnv();
const { db, pool } = createDb(env.DATABASE_URL);

await db
  .insert(taskRules)
  .values([
    { key: 'wird', labelAr: 'وِرد القرآن', labelEn: 'Quran wird', points: 20, sortOrder: 1 },
    { key: 'morning_azkar', labelAr: 'أذكار الصباح', labelEn: 'Morning azkar', points: 10, sortOrder: 2 },
    { key: 'five_prayers', labelAr: 'الصلوات الخمس', labelEn: 'Five prayers', points: 25, sortOrder: 3 },
    { key: 'evening_azkar', labelAr: 'أذكار المساء', labelEn: 'Evening azkar', points: 10, sortOrder: 4 },
    { key: 'listen', labelAr: 'الاستماع', labelEn: 'Listening', points: 10, sortOrder: 5 },
    { key: 'daily_task', labelAr: 'مهمة اليوم', labelEn: 'Daily task', points: 25, sortOrder: 6 },
  ])
  .onConflictDoNothing();

// Proposed values (incl. Ramadan) — disabled until the product owner confirms them.
await ensureBonusRules(db);

// Proposed streak milestones — disabled until approved; edit in the dashboard.
await db
  .insert(streakMilestones)
  .values([
    { days: 7, points: 50, labelAr: 'أسبوع من المواظبة', active: false },
    { days: 30, points: 200, labelAr: 'شهر من المواظبة', active: false },
    { days: 100, points: 500, labelAr: '100 يوم من اليقين', active: false },
  ])
  .onConflictDoNothing();

// Launch reciters (spec §5.14). Audio is served from our CDN once each recitation is licensed
// (spec §10) — upload `<id>/<surah:03>.mp3` + `<id>/timings.json`, then keep `active` on.
const CDN = process.env.AUDIO_CDN_BASE ?? 'https://cdn.yaqin-brand.com/audio';
const launchReciters = [
  { id: 'alafasy', nameAr: 'مشاري راشد العفاسي', nameEn: 'Mishary Rashid Alafasy', style: 'murattal', sizeBytes: 1_100_000_000 },
  { id: 'abdulbasit', nameAr: 'عبد الباسط عبد الصمد', nameEn: 'Abdul Basit Abdul Samad', style: 'murattal', sizeBytes: 1_300_000_000 },
  { id: 'husary', nameAr: 'محمود خليل الحصري', nameEn: 'Mahmoud Khalil Al-Husary', style: 'murattal', sizeBytes: 1_200_000_000 },
  { id: 'minshawi', nameAr: 'محمد صديق المنشاوي', nameEn: 'Mohamed Siddiq El-Minshawi', style: 'mujawwad', sizeBytes: 1_600_000_000 },
  { id: 'muaiqly', nameAr: 'ماهر المعيقلي', nameEn: 'Maher Al-Muaiqly', style: 'murattal', sizeBytes: 900_000_000 },
  { id: 'shuraim', nameAr: 'سعود الشريم', nameEn: 'Saud Al-Shuraim', style: 'murattal', sizeBytes: 800_000_000 },
  { id: 'sudais', nameAr: 'عبد الرحمن السديس', nameEn: 'Abdul Rahman Al-Sudais', style: 'murattal', sizeBytes: 850_000_000 },
];
await db
  .insert(reciters)
  .values(
    launchReciters.map((r, i) => ({
      ...r,
      riwaya: 'hafs',
      baseUrl: `${CDN}/${r.id}`,
      timingUrl: `${CDN}/${r.id}/timings.json`,
      sampleUrl: `${CDN}/${r.id}/001.mp3`,
      sortOrder: i,
    })),
  )
  .onConflictDoNothing();

const existingRewards = await db.select({ id: rewards.id }).from(rewards).limit(1);
if (existingRewards.length === 0) {
  await db.insert(rewards).values([
    { titleAr: 'خصم 50 جنيه', titleEn: '50 EGP off', kind: 'fixed_amount', value: 50, costPoints: 1000 },
    {
      titleAr: 'خصم 15% على سجادات الصلاة',
      titleEn: '15% off prayer rugs',
      kind: 'percentage',
      value: 15,
      costPoints: 2500,
      // Fill with the Shopify collection GID for prayer rugs (السكينة الذهبية، القِبلة، عبق اليقين).
      shopifyCollectionIds: [],
    },
    { titleAr: 'شحن مجاني', titleEn: 'Free shipping', kind: 'free_shipping', value: 0, costPoints: 4000 },
  ]);
}

await db
  .insert(contentItems)
  .values([
    {
      type: 'zikr',
      category: 'morning',
      title: 'سيد الاستغفار',
      textAr:
        'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ',
      source: 'صحيح البخاري 6306',
      repeatCount: 1,
      status: 'draft',
    },
  ])
  .onConflictDoNothing();

/**
 * Tafsir pack (spec §6.6, §10): التفسير الميسر from QuranEnc.com, built unaltered by
 * tools/tafsir/build_pack.py. Registered only when the hosted file's metadata is provided, so no
 * pack ever points at a file that doesn't exist. TAFSIR_PACK_VERSION is an integer you bump on each
 * rebuild (the app updates installed packs to a higher version); the source version goes in the title.
 */
const pack = {
  url: process.env.TAFSIR_PACK_URL,
  sha256: process.env.TAFSIR_PACK_SHA256,
  size: Number(process.env.TAFSIR_PACK_SIZE ?? 0),
  version: Number(process.env.TAFSIR_PACK_VERSION ?? 1),
  sourceVersion: process.env.TAFSIR_SOURCE_VERSION ?? '',
};
if (pack.url && pack.sha256 && /^[0-9a-f]{64}$/.test(pack.sha256) && pack.size > 0) {
  const row = {
    id: 'tafsir-muyassar',
    kind: 'tafsir' as const,
    titleAr: 'التفسير الميسر',
    titleEn: `Al-Tafsir al-Muyassar${pack.sourceVersion ? ` (QuranEnc v${pack.sourceVersion})` : ''}`,
    version: pack.version,
    url: pack.url,
    sha256: pack.sha256,
    sizeBytes: pack.size,
    active: true,
  };
  await db.insert(contentPacks).values(row).onConflictDoUpdate({ target: contentPacks.id, set: row });
  console.log(`Tafsir pack registered: v${pack.version} · ${pack.size} bytes`);
}

const email = process.env.SEED_ADMIN_EMAIL;
const password = process.env.SEED_ADMIN_PASSWORD;
if (email && password) {
  const totpSecret = generateTotpSecret();
  const inserted = await db
    .insert(adminUsers)
    .values({
      name: 'Super Admin',
      email,
      passwordHash: await hashPassword(password),
      totpSecret: sealSecret(totpSecret, secretsKey(process.env.ADMIN_SECRETS_KEY ?? '')),
      role: 'super_admin',
    })
    .onConflictDoNothing()
    .returning({ id: adminUsers.id });
  if (inserted.length) {
    console.log(`\nSuper admin created: ${email}`);
    console.log(`Add this to your authenticator app (shown once):`);
    console.log(`otpauth://totp/Yaqeen:${encodeURIComponent(email)}?secret=${totpSecret}&issuer=Yaqeen\n`);
  }
} else {
  console.log('Skipping admin: set SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD to create one.');
}

await pool.end();
console.log('Seed complete.');
