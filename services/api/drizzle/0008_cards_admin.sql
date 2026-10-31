CREATE TABLE "card_daily_stats" (
	"date" date NOT NULL,
	"metric" text NOT NULL,
	"value" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "card_daily_stats_date_metric_pk" PRIMARY KEY("date","metric")
);
--> statement-breakpoint
CREATE TABLE "tag_batches" (
	"batch" text PRIMARY KEY NOT NULL,
	"kind" text DEFAULT 'medal' NOT NULL,
	"status" text DEFAULT 'ordered' NOT NULL,
	"note" text DEFAULT '' NOT NULL,
	"created_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "public_profiles" ADD COLUMN "moderated_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "public_profiles" ADD COLUMN "moderation_reason" text;--> statement-breakpoint
ALTER TABLE "tag_batches" ADD CONSTRAINT "tag_batches_created_by_admin_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."admin_users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
-- Batches minted before batch tracking existed are already in the field.
INSERT INTO "tag_batches" ("batch", "kind", "status", "created_at")
SELECT "batch", min("kind"), 'on_sale', min("created_at") FROM "profile_tags" GROUP BY "batch"
ON CONFLICT DO NOTHING;
