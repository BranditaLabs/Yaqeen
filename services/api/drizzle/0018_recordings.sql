CREATE TABLE "recording_comments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"recording_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"text" text NOT NULL,
	"status" text DEFAULT 'visible' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"removed_at" timestamp with time zone,
	CONSTRAINT "recording_comments_status_ck" CHECK ("recording_comments"."status" in ('visible', 'hidden', 'removed')),
	CONSTRAINT "recording_comments_text_ck" CHECK (char_length("recording_comments"."text") <= 280)
);
--> statement-breakpoint
CREATE TABLE "recording_daily" (
	"user_id" uuid NOT NULL,
	"day" date NOT NULL,
	"count" smallint DEFAULT 0 NOT NULL,
	CONSTRAINT "recording_daily_user_id_day_pk" PRIMARY KEY("user_id","day")
);
--> statement-breakpoint
CREATE TABLE "recording_reactions" (
	"recording_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "recording_reactions_recording_id_user_id_pk" PRIMARY KEY("recording_id","user_id"),
	CONSTRAINT "recording_reactions_kind_ck" CHECK ("recording_reactions"."kind" in ('mashallah', 'barakallah', 'ahsant'))
);
--> statement-breakpoint
CREATE TABLE "recording_reports" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"target" text NOT NULL,
	"target_id" uuid NOT NULL,
	"reporter_id" uuid NOT NULL,
	"reason" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"resolved_by" uuid,
	"resolution" text,
	CONSTRAINT "recording_reports_target_ck" CHECK ("recording_reports"."target" in ('recording', 'comment')),
	CONSTRAINT "recording_reports_reason_ck" CHECK ("recording_reports"."reason" in ('not_recitation', 'inappropriate', 'spam', 'other')),
	CONSTRAINT "recording_reports_resolution_ck" CHECK ("recording_reports"."resolution" in ('dismissed', 'actioned'))
);
--> statement-breakpoint
CREATE TABLE "recordings" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"surah" smallint NOT NULL,
	"from_ayah" smallint NOT NULL,
	"to_ayah" smallint NOT NULL,
	"duration_ms" integer NOT NULL,
	"audio" "bytea" NOT NULL,
	"bytes" integer NOT NULL,
	"status" text NOT NULL,
	"reject_reason" text,
	"score" real,
	"speech" real,
	"words" jsonb,
	"visibility" text DEFAULT 'private' NOT NULL,
	"comments_on" boolean DEFAULT true NOT NULL,
	"position" smallint NOT NULL,
	"asr_attempts" smallint DEFAULT 0 NOT NULL,
	"queued_at" timestamp with time zone,
	"transcript" text,
	"client_score" real,
	"client_words" jsonb,
	"held_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"verified_at" timestamp with time zone,
	"removed_at" timestamp with time zone,
	CONSTRAINT "recordings_status_ck" CHECK ("recordings"."status" in ('processing', 'private_ready', 'approved', 'needs_review', 'rejected', 'removed')),
	CONSTRAINT "recordings_reject_reason_ck" CHECK ("recordings"."reject_reason" in ('not_matching', 'unclear', 'silence', 'too_long', 'removed_by_moderator')),
	CONSTRAINT "recordings_visibility_ck" CHECK ("recordings"."visibility" in ('private', 'members', 'public')),
	CONSTRAINT "recordings_range_ck" CHECK ("recordings"."surah" between 1 and 114 and "recordings"."from_ayah" >= 1 and "recordings"."from_ayah" <= "recordings"."to_ayah"),
	CONSTRAINT "recordings_duration_ck" CHECK ("recordings"."duration_ms" between 0 and 31000),
	CONSTRAINT "recordings_bytes_ck" CHECK ("recordings"."bytes" <= 200000),
	CONSTRAINT "recordings_position_ck" CHECK ("recordings"."position" between 1 and 3)
);
--> statement-breakpoint
ALTER TABLE "recording_comments" ADD CONSTRAINT "recording_comments_recording_id_recordings_id_fk" FOREIGN KEY ("recording_id") REFERENCES "public"."recordings"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recording_comments" ADD CONSTRAINT "recording_comments_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recording_daily" ADD CONSTRAINT "recording_daily_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recording_reactions" ADD CONSTRAINT "recording_reactions_recording_id_recordings_id_fk" FOREIGN KEY ("recording_id") REFERENCES "public"."recordings"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recording_reactions" ADD CONSTRAINT "recording_reactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recording_reports" ADD CONSTRAINT "recording_reports_reporter_id_users_id_fk" FOREIGN KEY ("reporter_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recording_reports" ADD CONSTRAINT "recording_reports_resolved_by_admin_users_id_fk" FOREIGN KEY ("resolved_by") REFERENCES "public"."admin_users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recordings" ADD CONSTRAINT "recordings_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "recording_comments_list_idx" ON "recording_comments" USING btree ("recording_id","created_at" DESC NULLS LAST,"id");--> statement-breakpoint
CREATE INDEX "recording_comments_user_idx" ON "recording_comments" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "recording_reactions_user_idx" ON "recording_reactions" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "recording_reports_uq" ON "recording_reports" USING btree ("target","target_id","reporter_id");--> statement-breakpoint
CREATE INDEX "recording_reports_open_idx" ON "recording_reports" USING btree ("target","target_id") WHERE "recording_reports"."resolved_at" is null;--> statement-breakpoint
CREATE INDEX "recording_reports_reporter_idx" ON "recording_reports" USING btree ("reporter_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "recordings_user_idx" ON "recordings" USING btree ("user_id","position");--> statement-breakpoint
CREATE INDEX "recordings_queue_idx" ON "recordings" USING btree ("status","created_at");