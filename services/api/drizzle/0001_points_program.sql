ALTER TYPE "public"."ledger_reason" ADD VALUE 'milestone' BEFORE 'qada';--> statement-breakpoint
ALTER TYPE "public"."ledger_reason" ADD VALUE 'grant' BEFORE 'qada';--> statement-breakpoint
CREATE TABLE "point_grants" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"segment" text NOT NULL,
	"points" integer NOT NULL,
	"reason_ar" text NOT NULL,
	"recipients" integer DEFAULT 0 NOT NULL,
	"created_by" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "streak_milestones" (
	"days" integer PRIMARY KEY NOT NULL,
	"points" integer NOT NULL,
	"label_ar" text NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "rewards" ADD COLUMN "per_user_monthly_limit" integer;--> statement-breakpoint
ALTER TABLE "task_rules" ADD COLUMN "active" boolean DEFAULT true NOT NULL;