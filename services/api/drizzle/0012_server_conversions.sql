CREATE TABLE "conversion_sends" (
	"order_id" text NOT NULL,
	"platform" text NOT NULL,
	"status" text NOT NULL,
	"attempts" smallint DEFAULT 1 NOT NULL,
	"sent_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "conversion_sends_order_id_platform_pk" PRIMARY KEY("order_id","platform")
);
--> statement-breakpoint
CREATE INDEX "conversion_sends_sent_idx" ON "conversion_sends" USING btree ("sent_at");