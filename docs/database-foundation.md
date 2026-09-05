# CHIC GIFT Database Foundation

Phase 1B defines the database structure and deny-by-default security boundary. It does not create a cloud project or implement Gift creation, opening, redemption, or Admin overrides.

## Structure

- `private` contains all eight application tables and privileged helpers. It must not be exposed through the Supabase Data API.
- `api` is reserved for narrow public and authenticated functions added in a later phase.
- Browser roles have no direct table permissions. RLS is enabled on every application table with no allow policies yet.
- `private.is_active_staff()` and `private.is_active_admin()` check the signed-in Supabase user against an active Staff profile. Future database functions and RLS policies should call these helpers rather than trusting the frontend.

## Lifecycle model

Campaign status is stored as `DRAFT`, `SCHEDULED`, `ACTIVE`, `PAUSED`, `ENDED`, or `ARCHIVED`. Status changes are manual. Future Gift creation must also check `start_at` and `end_at`.

Gift status stores only `ELIGIBLE`, `OPENED`, or `CANCELLED`. Reward state is derived:

- redeemed when `redeemed_at` is present;
- expired when it is not redeemed and `expires_at` has passed;
- available otherwise.

This avoids duplicated Gift and Reward statuses that could disagree.

## Important protections

- Bill Codes are trimmed and uppercased by the database. Internal whitespace is rejected.
- `(branch_id, bill_code_normalized)` is unique.
- Each branch can have only one `ACTIVE` campaign.
- Each Gift Token and Reward Code is unique.
- Each Gift can have at most one Reward.
- VND values use integer storage with nonnegative checks.
- A published Campaign Version requires one active, unlimited fallback Prize.
- The fallback is structurally separate from normal Prizes. Future selection logic must use it only after no normal Prize remains eligible; “low cost” is a business review, not a database threshold.
- Published version and Prize configuration cannot be inserted, changed, or deleted silently. Only `issued_quantity` may increase within its configured limit.
- Audit rows cannot be updated or deleted.
- Historical foreign keys use restricted deletion.

## Development seed

`supabase/seed.sql` adds one non-production branch named `CHIC-DEV`. It creates no credentials, Campaigns, Prizes, Gifts, Rewards, or customer data.

## Retention and future overrides

Campaign, Gift, Reward, and Audit history must remain for at least 12 months after the final Reward expires. The MVP has no automatic deletion.

Future Admin functions may correct or cancel an eligible Gift and may extend or exceptionally cancel an opened Reward, always with a reason and Audit entry. They must never reroll or replace an issued Prize, reduce issued value, worsen historical terms, or reverse a redemption. Phase 1B implements none of these operations.

## Validation

`supabase/tests/phase_1b_foundation.test.sql` contains isolated database checks and rolls back all fixtures. Run it only after applying migrations to a disposable Supabase development database.

This machine currently has neither PostgreSQL nor the Supabase CLI. Phase 1B therefore uses static review instead of installing Docker or a local database solely for testing. The SQL test suite must be executed before this schema is accepted for production use.
