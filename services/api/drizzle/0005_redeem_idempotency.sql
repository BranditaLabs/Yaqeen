ALTER TABLE "redemptions" ADD COLUMN "idempotency_key" text;--> statement-breakpoint
CREATE UNIQUE INDEX "redemptions_user_idem_uq" ON "redemptions" USING btree ("user_id","idempotency_key");