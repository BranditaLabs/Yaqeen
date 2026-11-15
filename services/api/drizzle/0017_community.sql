ALTER TYPE "public"."consent_kind" ADD VALUE 'community';--> statement-breakpoint
CREATE TABLE "avatar_photos" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"sha_small" text NOT NULL,
	"sha_large" text NOT NULL,
	"small" "bytea" NOT NULL,
	"large" "bytea" NOT NULL,
	"bytes" integer NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"removed_at" timestamp with time zone,
	"removed_by" uuid,
	"removed_reason" text,
	CONSTRAINT "avatar_photos_status_ck" CHECK ("avatar_photos"."status" in ('active', 'replaced', 'removed'))
);
--> statement-breakpoint
CREATE TABLE "community_blocks" (
	"user_id" uuid NOT NULL,
	"blocked_user_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "community_blocks_user_id_blocked_user_id_pk" PRIMARY KEY("user_id","blocked_user_id"),
	CONSTRAINT "community_blocks_not_self_ck" CHECK ("community_blocks"."user_id" <> "community_blocks"."blocked_user_id")
);
--> statement-breakpoint
CREATE TABLE "community_members" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"leagues" boolean DEFAULT false NOT NULL,
	"leaderboard" boolean DEFAULT false NOT NULL,
	"leaderboard_country" boolean DEFAULT false NOT NULL,
	"division" smallint DEFAULT 1 NOT NULL,
	"banned_at" timestamp with time zone,
	"banned_reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "community_members_division_ck" CHECK ("community_members"."division" between 1 and 6)
);
--> statement-breakpoint
CREATE TABLE "community_reports" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"reporter_id" uuid NOT NULL,
	"target_user_id" uuid NOT NULL,
	"reason" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"resolved_by" uuid,
	"resolution" text,
	CONSTRAINT "community_reports_reason_ck" CHECK ("community_reports"."reason" in ('name', 'photo', 'other')),
	CONSTRAINT "community_reports_resolution_ck" CHECK ("community_reports"."resolution" in ('dismissed', 'actioned'))
);
--> statement-breakpoint
CREATE TABLE "community_snapshot_days" (
	"day" date PRIMARY KEY NOT NULL,
	"taken_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "leaderboard_snapshot" (
	"scope" text NOT NULL,
	"country" text DEFAULT '' NOT NULL,
	"user_id" uuid NOT NULL,
	"rank" integer NOT NULL,
	"lifetime" integer NOT NULL,
	"day" date NOT NULL,
	CONSTRAINT "leaderboard_snapshot_scope_country_user_id_pk" PRIMARY KEY("scope","country","user_id"),
	CONSTRAINT "leaderboard_snapshot_scope_ck" CHECK ("leaderboard_snapshot"."scope" in ('global', 'country'))
);
--> statement-breakpoint
CREATE TABLE "league_groups" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"starts_on" date NOT NULL,
	"division" smallint NOT NULL,
	"size" smallint DEFAULT 0 NOT NULL,
	"closed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "league_groups_division_ck" CHECK ("league_groups"."division" between 1 and 6)
);
--> statement-breakpoint
CREATE TABLE "league_members" (
	"starts_on" date NOT NULL,
	"user_id" uuid NOT NULL,
	"group_id" uuid NOT NULL,
	"division" smallint NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"left_at" timestamp with time zone,
	"snapshot_points" integer,
	"snapshot_rank" smallint,
	"final_points" integer,
	"final_rank" smallint,
	"outcome" text,
	CONSTRAINT "league_members_starts_on_user_id_pk" PRIMARY KEY("starts_on","user_id"),
	CONSTRAINT "league_members_division_ck" CHECK ("league_members"."division" between 1 and 6),
	CONSTRAINT "league_members_outcome_ck" CHECK ("league_members"."outcome" in ('up', 'stay', 'down'))
);
--> statement-breakpoint
CREATE TABLE "league_weeks" (
	"starts_on" date PRIMARY KEY NOT NULL,
	"starts_at" timestamp with time zone NOT NULL,
	"ends_at" timestamp with time zone NOT NULL,
	"settings" jsonb,
	"status" text DEFAULT 'open' NOT NULL,
	"closed_at" timestamp with time zone,
	CONSTRAINT "league_weeks_status_ck" CHECK ("league_weeks"."status" in ('open', 'closed'))
);
--> statement-breakpoint
CREATE TABLE "points_earned_daily" (
	"user_id" uuid NOT NULL,
	"day" date NOT NULL,
	"earned" integer NOT NULL,
	CONSTRAINT "points_earned_daily_user_id_day_pk" PRIMARY KEY("user_id","day")
);
--> statement-breakpoint
CREATE TABLE "tournament_entries" (
	"tournament_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"left_at" timestamp with time zone,
	"snapshot_points" integer,
	"snapshot_rank" integer,
	"final_points" integer,
	"final_rank" integer,
	CONSTRAINT "tournament_entries_tournament_id_user_id_pk" PRIMARY KEY("tournament_id","user_id")
);
--> statement-breakpoint
CREATE TABLE "tournaments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"slug" text NOT NULL,
	"title_ar" text NOT NULL,
	"title_en" text NOT NULL,
	"body_ar" text DEFAULT '' NOT NULL,
	"body_en" text DEFAULT '' NOT NULL,
	"starts_at" timestamp with time zone NOT NULL,
	"ends_at" timestamp with time zone NOT NULL,
	"join_until" timestamp with time zone NOT NULL,
	"badge_ar" text NOT NULL,
	"badge_en" text NOT NULL,
	"min_points" integer DEFAULT 1 NOT NULL,
	"status" text DEFAULT 'draft' NOT NULL,
	"finalizing_at" timestamp with time zone,
	"closed_at" timestamp with time zone,
	"created_by" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "tournaments_slug_ck" CHECK ("tournaments"."slug" ~ '^[a-z0-9-]{3,40}$'),
	CONSTRAINT "tournaments_titles_ck" CHECK (char_length("tournaments"."title_ar") <= 60 and char_length("tournaments"."title_en") <= 60),
	CONSTRAINT "tournaments_bodies_ck" CHECK (char_length("tournaments"."body_ar") <= 280 and char_length("tournaments"."body_en") <= 280),
	CONSTRAINT "tournaments_badges_ck" CHECK (char_length("tournaments"."badge_ar") <= 40 and char_length("tournaments"."badge_en") <= 40),
	CONSTRAINT "tournaments_status_ck" CHECK ("tournaments"."status" in ('draft', 'published', 'cancelled')),
	CONSTRAINT "tournaments_window_ck" CHECK ("tournaments"."starts_at" < "tournaments"."ends_at" and "tournaments"."join_until" <= "tournaments"."ends_at"),
	CONSTRAINT "tournaments_window_len_ck" CHECK ("tournaments"."ends_at" - "tournaments"."starts_at" <= interval '90 days'),
	CONSTRAINT "tournaments_min_points_ck" CHECK ("tournaments"."min_points" >= 1)
);
--> statement-breakpoint
CREATE TABLE "user_badges" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"ref_key" text NOT NULL,
	"meta" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"awarded_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_badges_kind_ck" CHECK ("user_badges"."kind" in ('league_first','league_top3','league_promoted','division_reached','tournament_podium','tournament_top10','tournament_finisher'))
);
--> statement-breakpoint
CREATE TABLE "user_point_totals" (
	"user_id" uuid PRIMARY KEY NOT NULL,
	"lifetime_earned" integer DEFAULT 0 NOT NULL,
	"public_lifetime" integer DEFAULT 0 NOT NULL,
	"public_day" date
);
--> statement-breakpoint
ALTER TABLE "consent_events" ADD COLUMN "attested_adult" boolean;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "country" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "avatar_kind" text DEFAULT 'initial' NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "avatar_preset" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "avatar_photo_id" uuid;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "name_hidden_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "name_hidden_reason" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "photo_locked_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "adult_attested_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "avatar_photos" ADD CONSTRAINT "avatar_photos_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "avatar_photos" ADD CONSTRAINT "avatar_photos_removed_by_admin_users_id_fk" FOREIGN KEY ("removed_by") REFERENCES "public"."admin_users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_blocks" ADD CONSTRAINT "community_blocks_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_blocks" ADD CONSTRAINT "community_blocks_blocked_user_id_users_id_fk" FOREIGN KEY ("blocked_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_members" ADD CONSTRAINT "community_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_reports" ADD CONSTRAINT "community_reports_reporter_id_users_id_fk" FOREIGN KEY ("reporter_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_reports" ADD CONSTRAINT "community_reports_target_user_id_users_id_fk" FOREIGN KEY ("target_user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "community_reports" ADD CONSTRAINT "community_reports_resolved_by_admin_users_id_fk" FOREIGN KEY ("resolved_by") REFERENCES "public"."admin_users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "leaderboard_snapshot" ADD CONSTRAINT "leaderboard_snapshot_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "league_groups" ADD CONSTRAINT "league_groups_starts_on_league_weeks_starts_on_fk" FOREIGN KEY ("starts_on") REFERENCES "public"."league_weeks"("starts_on") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "league_members" ADD CONSTRAINT "league_members_starts_on_league_weeks_starts_on_fk" FOREIGN KEY ("starts_on") REFERENCES "public"."league_weeks"("starts_on") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "league_members" ADD CONSTRAINT "league_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "league_members" ADD CONSTRAINT "league_members_group_id_league_groups_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."league_groups"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "points_earned_daily" ADD CONSTRAINT "points_earned_daily_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tournament_entries" ADD CONSTRAINT "tournament_entries_tournament_id_tournaments_id_fk" FOREIGN KEY ("tournament_id") REFERENCES "public"."tournaments"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tournament_entries" ADD CONSTRAINT "tournament_entries_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tournaments" ADD CONSTRAINT "tournaments_created_by_admin_users_id_fk" FOREIGN KEY ("created_by") REFERENCES "public"."admin_users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_point_totals" ADD CONSTRAINT "user_point_totals_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "avatar_photos_user_idx" ON "avatar_photos" USING btree ("user_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "avatar_photos_status_idx" ON "avatar_photos" USING btree ("status","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "community_blocks_blocked_idx" ON "community_blocks" USING btree ("blocked_user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "community_reports_open_uq" ON "community_reports" USING btree ("reporter_id","target_user_id") WHERE "community_reports"."resolved_at" is null;--> statement-breakpoint
CREATE INDEX "community_reports_reporter_idx" ON "community_reports" USING btree ("reporter_id","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "leaderboard_snapshot_rank_idx" ON "leaderboard_snapshot" USING btree ("scope","country","rank");--> statement-breakpoint
CREATE INDEX "league_groups_fill_idx" ON "league_groups" USING btree ("starts_on","division","size");--> statement-breakpoint
CREATE INDEX "league_groups_open_idx" ON "league_groups" USING btree ("starts_on") WHERE "league_groups"."closed_at" is null;--> statement-breakpoint
CREATE INDEX "league_members_group_rank_idx" ON "league_members" USING btree ("group_id","snapshot_rank");--> statement-breakpoint
CREATE INDEX "points_earned_daily_day_idx" ON "points_earned_daily" USING btree ("day","user_id");--> statement-breakpoint
CREATE INDEX "tournament_entries_snapshot_idx" ON "tournament_entries" USING btree ("tournament_id","snapshot_rank");--> statement-breakpoint
CREATE INDEX "tournament_entries_final_idx" ON "tournament_entries" USING btree ("tournament_id","final_rank");--> statement-breakpoint
CREATE UNIQUE INDEX "tournaments_slug_uq" ON "tournaments" USING btree ("slug");--> statement-breakpoint
CREATE UNIQUE INDEX "user_badges_user_ref_uq" ON "user_badges" USING btree ("user_id","ref_key");--> statement-breakpoint
CREATE INDEX "user_point_totals_public_idx" ON "user_point_totals" USING btree ("public_lifetime" DESC NULLS LAST);--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_avatar_photo_id_avatar_photos_id_fk" FOREIGN KEY ("avatar_photo_id") REFERENCES "public"."avatar_photos"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_country_ck" CHECK ("users"."country" ~ '^[A-Z]{2}$');--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_avatar_kind_ck" CHECK ("users"."avatar_kind" in ('initial', 'preset', 'photo'));--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_avatar_preset_ck" CHECK ("users"."avatar_preset" in ('m01','m02','m03','m04','m05','m06','m07','m08','f01','f02','f03','f04','f05','f06','f07','f08'));--> statement-breakpoint
ALTER TABLE "users" ADD CONSTRAINT "users_avatar_preset_required_ck" CHECK ("users"."avatar_kind" <> 'preset' or "users"."avatar_preset" is not null);--> statement-breakpoint
-- Hand-written (docs/design/2026-11-profile-community-quran.md §2). Derived rollups of the append-only
-- points ledger: `points_earned_daily` (contracts EARNED_REASONS, per Africa/Cairo day) and
-- `user_point_totals.lifetime_earned` (contracts LEVEL_REASONS). They are caches, not balances: the
-- trigger only reads NEW, and `select yq_rebuild_points_rollups();` recomputes both from the ledger.
CREATE OR REPLACE FUNCTION yq_points_rollup() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.delta > 0 AND NEW.reason::text IN ('task', 'qada', 'bonus', 'milestone') THEN
    INSERT INTO points_earned_daily (user_id, day, earned)
    VALUES (NEW.user_id, (NEW.created_at AT TIME ZONE 'Africa/Cairo')::date, NEW.delta)
    ON CONFLICT (user_id, day) DO UPDATE SET earned = points_earned_daily.earned + EXCLUDED.earned;
  END IF;
  IF NEW.delta > 0 AND NEW.reason::text IN ('task', 'qada', 'bonus', 'milestone', 'grant', 'admin_adjustment') THEN
    INSERT INTO user_point_totals (user_id, lifetime_earned)
    VALUES (NEW.user_id, NEW.delta)
    ON CONFLICT (user_id) DO UPDATE SET lifetime_earned = user_point_totals.lifetime_earned + EXCLUDED.lifetime_earned;
  END IF;
  RETURN NULL;
END;
$$;--> statement-breakpoint
CREATE TRIGGER points_ledger_rollup AFTER INSERT ON points_ledger FOR EACH ROW EXECUTE FUNCTION yq_points_rollup();--> statement-breakpoint
-- Truncate and recompute. Daily rows follow a merged guest to its account (users.merged_into);
-- lifetime stays per ledger user_id; public_lifetime is reset to lifetime_earned (public_day null until
-- the next nightly snapshot stamps it).
CREATE OR REPLACE FUNCTION yq_rebuild_points_rollups() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  TRUNCATE points_earned_daily, user_point_totals;
  INSERT INTO points_earned_daily (user_id, day, earned)
  SELECT coalesce(u.merged_into, l.user_id), (l.created_at AT TIME ZONE 'Africa/Cairo')::date, sum(l.delta)::integer
  FROM points_ledger l
  JOIN users u ON u.id = l.user_id
  WHERE l.delta > 0 AND l.reason::text IN ('task', 'qada', 'bonus', 'milestone')
  GROUP BY 1, 2;
  INSERT INTO user_point_totals (user_id, lifetime_earned, public_lifetime)
  SELECT l.user_id, sum(l.delta)::integer, sum(l.delta)::integer
  FROM points_ledger l
  WHERE l.delta > 0 AND l.reason::text IN ('task', 'qada', 'bonus', 'milestone', 'grant', 'admin_adjustment')
  GROUP BY 1;
END;
$$;--> statement-breakpoint
SELECT yq_rebuild_points_rollups();
