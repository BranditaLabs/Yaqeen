/**
 * Seed reference data: task rules, bonus rules (disabled until approved), rewards, a first
 * super admin, and sample content in DRAFT (must pass religious review before publishing).
 *
 *   SEED_ADMIN_EMAIL=you@yaqin-brand.com SEED_ADMIN_PASSWORD='…' pnpm db:seed
 */
import { loadEnv } from '../config/env.js';
import { generateTotpSecret, hashPassword } from '../lib/crypto.js';
import { createDb } from './client.js';
import { adminUsers, bonusRules, contentItems, rewards, streakMilestones, taskRules } from './schema.js';

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

// Proposed values — disabled until the product owner confirms them.
await db
  .insert(bonusRules)
  .values([
    { kind: 'white_days_fast', labelAr: 'صيام الأيام البيض', points: 30, enabled: false },
    { kind: 'mon_thu_fast', labelAr: 'صيام الاثنين والخميس', points: 30, enabled: false },
    { kind: 'friday_kahf', labelAr: 'سورة الكهف يوم الجمعة', points: 20, enabled: false },
  ])
  .onConflictDoNothing();

// Proposed streak milestones — disabled until approved; edit in the dashboard.
await db
  .insert(streakMilestones)
  .values([
    { days: 7, points: 50, labelAr: 'أسبوع من المواظبة', active: false },
    { days: 30, points: 200, labelAr: 'شهر من المواظبة', active: false },
    { days: 100, points: 500, labelAr: '100 يوم من اليقين', active: false },
  ])
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
      category: 'أذكار الصباح',
      title: 'سيد الاستغفار',
      textAr:
        'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ',
      source: 'صحيح البخاري 6306',
      repeatCount: 1,
      status: 'draft',
    },
  ])
  .onConflictDoNothing();

const email = process.env.SEED_ADMIN_EMAIL;
const password = process.env.SEED_ADMIN_PASSWORD;
if (email && password) {
  const totpSecret = generateTotpSecret();
  const inserted = await db
    .insert(adminUsers)
    .values({ name: 'Super Admin', email, passwordHash: await hashPassword(password), totpSecret, role: 'super_admin' })
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
