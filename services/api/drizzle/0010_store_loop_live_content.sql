ALTER TABLE "content_items" ADD COLUMN "live" jsonb;--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN "live_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "redemptions" ADD COLUMN "used_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "redemptions" ADD COLUMN "shopify_order_id" text;--> statement-breakpoint
CREATE INDEX "content_items_live_idx" ON "content_items" USING btree ("type","live_at");--> statement-breakpoint
CREATE INDEX "redemptions_status_expires_idx" ON "redemptions" USING btree ("status","expires_at");--> statement-breakpoint
-- Items already published become the live version.
UPDATE "content_items" SET
  "live" = jsonb_build_object(
    'category', "category", 'title', "title", 'textAr', "text_ar", 'translationEn', "translation_en",
    'source', "source", 'virtue', "virtue", 'repeatCount', "repeat_count", 'sortOrder', "sort_order",
    'featured', "featured", 'version', "version"),
  "live_at" = coalesce("published_at", "updated_at")
WHERE "status" = 'published';
