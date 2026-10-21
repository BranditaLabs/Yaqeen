ALTER TABLE "content_items" ADD COLUMN "virtue" text;--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN "sort_order" smallint DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN "featured" boolean DEFAULT false NOT NULL;--> statement-breakpoint
-- Free-text categories from v1 → stable keys the app maps to tabs (contracts ZIKR/DUA_CATEGORIES).
UPDATE "content_items" SET "category" = CASE "category"
  WHEN 'أذكار الصباح' THEN 'morning'
  WHEN 'أذكار المساء' THEN 'evening'
  WHEN 'أذكار بعد الصلاة' THEN 'after_prayer'
  WHEN 'أذكار النوم' THEN 'sleep'
  WHEN 'النوم' THEN 'sleep'
  WHEN 'الهم والحزن' THEN 'worry'
  WHEN 'أدعية السفر' THEN 'travel'
  WHEN 'السفر' THEN 'travel'
  WHEN 'الطعام' THEN 'food'
  WHEN 'المسجد' THEN 'mosque'
  WHEN 'عام' THEN 'general'
  ELSE "category" END
WHERE "type" IN ('dua', 'zikr');
