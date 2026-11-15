CREATE TABLE "profile_tags" (
	"code" text PRIMARY KEY NOT NULL,
	"kind" text DEFAULT 'medal' NOT NULL,
	"batch" text NOT NULL,
	"user_id" uuid,
	"linked_at" timestamp with time zone,
	"disabled_at" timestamp with time zone,
	"scans" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "profile_tags" ADD CONSTRAINT "profile_tags_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "profile_tags_user_idx" ON "profile_tags" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "profile_tags_batch_idx" ON "profile_tags" USING btree ("batch");