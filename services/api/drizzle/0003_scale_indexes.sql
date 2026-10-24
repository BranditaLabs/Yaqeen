CREATE INDEX "campaigns_status_scheduled_idx" ON "campaigns" USING btree ("status","scheduled_at");--> statement-breakpoint
CREATE INDEX "consents_kind_granted_idx" ON "consents" USING btree ("kind","granted");--> statement-breakpoint
CREATE INDEX "redemptions_reward_created_idx" ON "redemptions" USING btree ("reward_id","created_at");--> statement-breakpoint
CREATE INDEX "refresh_tokens_user_idx" ON "refresh_tokens" USING btree ("user_id");