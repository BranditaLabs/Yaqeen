ALTER TABLE "reciters" ALTER COLUMN "base_url" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "reciters" ALTER COLUMN "size_bytes" SET DATA TYPE bigint;--> statement-breakpoint
ALTER TABLE "reciters" ADD COLUMN "source" text DEFAULT 'own' NOT NULL;--> statement-breakpoint
ALTER TABLE "reciters" ADD COLUMN "qf_id" integer;--> statement-breakpoint
-- Audio now comes from Quran.com / Quran Foundation (owner decision, spec §10): point the launch
-- reciters at their chapter-reciter ids and drop the placeholder CDN URLs (no files were ever there).
UPDATE "reciters" SET "source" = 'qf', "base_url" = NULL, "timing_url" = NULL, "sample_url" = NULL,
  "qf_id" = CASE "id" WHEN 'alafasy' THEN 7 WHEN 'abdulbasit' THEN 2 WHEN 'husary' THEN 6 WHEN 'minshawi' THEN 9
    WHEN 'shuraim' THEN 10 WHEN 'sudais' THEN 3 END,
  "style" = CASE "id" WHEN 'minshawi' THEN 'murattal' ELSE "style" END,
  "updated_at" = now()
WHERE "id" IN ('alafasy', 'abdulbasit', 'husary', 'minshawi', 'shuraim', 'sudais') AND "base_url" LIKE 'https://cdn.yaqin-brand.com/audio/%';--> statement-breakpoint
-- Not offered by Quran Foundation as a chapter reciter: hidden until we host it ourselves.
UPDATE "reciters" SET "active" = false, "updated_at" = now() WHERE "id" = 'muaiqly' AND "base_url" LIKE 'https://cdn.yaqin-brand.com/audio/%';
