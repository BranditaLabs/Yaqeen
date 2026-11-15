ALTER TABLE "daily_tasks" ADD COLUMN "status" "content_status" DEFAULT 'pending_review' NOT NULL;--> statement-breakpoint
ALTER TABLE "daily_tasks" ADD COLUMN "reviewed_by" uuid;--> statement-breakpoint
ALTER TABLE "daily_tasks" ADD COLUMN "review_note" text;--> statement-breakpoint
ALTER TABLE "daily_tasks" ADD COLUMN "live" jsonb;--> statement-breakpoint
ALTER TABLE "daily_tasks" ADD COLUMN "live_at" timestamp with time zone;
-- Existing tasks were never reviewed: they wait in pending_review (no `live`) until a religious
-- reviewer approves them (CLAUDE rule 4).
