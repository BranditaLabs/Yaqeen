CREATE TABLE "tag_encode_sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"batch" text NOT NULL,
	"token_hash" text NOT NULL,
	"created_by" uuid,
	"expires_at" timestamp with time zone NOT NULL,
	"revoked_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tag_encode_sessions_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
ALTER TABLE "profile_tags" ADD COLUMN "encoded_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "profile_tags" ADD COLUMN "encoded_uid" text;--> statement-breakpoint
ALTER TABLE "profile_tags" ADD COLUMN "encoded_locked" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "tag_encode_sessions" ADD CONSTRAINT "tag_encode_sessions_batch_tag_batches_batch_fk" FOREIGN KEY ("batch") REFERENCES "public"."tag_batches"("batch") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tag_encode_sessions" ADD CONSTRAINT "tag_encode_sessions_created_by_admin_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."admin_users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "tag_encode_sessions_batch_idx" ON "tag_encode_sessions" USING btree ("batch");