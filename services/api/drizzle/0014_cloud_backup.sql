ALTER TYPE "public"."consent_kind" ADD VALUE 'cloud_backup';--> statement-breakpoint
CREATE TABLE "user_backups" (
	"user_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"blob" text NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"device_id" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_backups_user_id_kind_pk" PRIMARY KEY("user_id","kind")
);
--> statement-breakpoint
ALTER TABLE "user_backups" ADD CONSTRAINT "user_backups_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;