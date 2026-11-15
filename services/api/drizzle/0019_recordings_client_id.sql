ALTER TABLE "recordings" ADD COLUMN "client_id" text;--> statement-breakpoint
CREATE UNIQUE INDEX "recordings_client_uq" ON "recordings" USING btree ("user_id","client_id");