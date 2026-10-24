CREATE TYPE "public"."pack_kind" AS ENUM('tafsir', 'font', 'audio', 'translation');--> statement-breakpoint
ALTER TYPE "public"."content_type" ADD VALUE 'splash_verse';--> statement-breakpoint
ALTER TYPE "public"."user_status" ADD VALUE 'deleted';--> statement-breakpoint
CREATE TABLE "content_packs" (
	"id" text PRIMARY KEY NOT NULL,
	"kind" "pack_kind" NOT NULL,
	"title_ar" text NOT NULL,
	"title_en" text NOT NULL,
	"version" integer NOT NULL,
	"url" text NOT NULL,
	"sha256" text NOT NULL,
	"size_bytes" integer NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "reciters" (
	"id" text PRIMARY KEY NOT NULL,
	"name_ar" text NOT NULL,
	"name_en" text NOT NULL,
	"style" text DEFAULT 'murattal' NOT NULL,
	"riwaya" text DEFAULT 'hafs' NOT NULL,
	"base_url" text NOT NULL,
	"timing_url" text,
	"sample_url" text,
	"size_bytes" integer DEFAULT 0 NOT NULL,
	"sort_order" smallint DEFAULT 0 NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "user_activity_days" (
	"user_id" uuid NOT NULL,
	"date" date NOT NULL,
	CONSTRAINT "user_activity_days_user_id_date_pk" PRIMARY KEY("user_id","date")
);
--> statement-breakpoint
ALTER TABLE "audit_log" ALTER COLUMN "admin_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "admin_users" ADD COLUMN "test_device_tokens" text[] DEFAULT '{}'::text[] NOT NULL;--> statement-breakpoint
ALTER TABLE "audit_log" ADD COLUMN "actor_user_id" uuid;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "merged_into" uuid;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "deletion_requested_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "user_activity_days" ADD CONSTRAINT "user_activity_days_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "user_activity_days_date_idx" ON "user_activity_days" USING btree ("date");