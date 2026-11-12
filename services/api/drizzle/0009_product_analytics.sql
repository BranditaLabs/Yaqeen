ALTER TYPE "public"."consent_kind" ADD VALUE 'product_analytics';--> statement-breakpoint
CREATE TABLE "product_events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"anon_id" uuid NOT NULL,
	"name" text NOT NULL,
	"props" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"platform" text NOT NULL,
	"app_version" text NOT NULL,
	"locale" text NOT NULL,
	"occurred_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "product_events_time_idx" ON "product_events" USING btree ("occurred_at");--> statement-breakpoint
CREATE INDEX "product_events_name_time_idx" ON "product_events" USING btree ("name","occurred_at");