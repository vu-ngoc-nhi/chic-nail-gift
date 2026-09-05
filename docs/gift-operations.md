# Gift Operation Contracts

Phase 1D exposes two narrow PostgreSQL functions through Supabase. Browser roles still have no direct access to internal tables.

The `api` schema is listed in `supabase/config.toml` for reproducible Data API configuration. A hosted environment must also list `api` in its Data API exposed schemas before browser integration; never expose `private`.

## Staff Gift creation

Call `api.create_gift(p_bill_code text, p_bill_amount_vnd bigint)` as an authenticated user. The function requires an active `STAFF` or `ADMIN` profile and uses that profile's active branch; the browser cannot select another branch.

The result contains only `result_code`, Gift identifiers needed to recover the future QR, normalized Bill information, Gift status, creation time, `is_new`, and the applicable campaign minimum.

Result codes:

- `CREATED_GIFT` — one new `ELIGIBLE` Gift was created.
- `EXISTING_GIFT` — the normalized Bill and amount already exist; the existing Gift and token are returned.
- `AMOUNT_MISMATCH` — the Bill exists with another amount; its token is withheld.
- `BILL_BELOW_MINIMUM` — amount is below the current Campaign Version minimum.
- `NO_ACTIVE_CAMPAIGN` — no published current version is active within its date window.
- `INVALID_BILL_CODE` or `INVALID_BILL_AMOUNT` — input is unusable.

Creation, duplicate recovery, and amount mismatch write `CREATE_GIFT`, `DUPLICATE_ATTEMPT`, and `AMOUNT_MISMATCH` Audit rows inside the same trusted transaction. PostgreSQL's branch/Bill uniqueness constraint resolves concurrent duplicates.

## Public Gift lookup

Call `api.get_public_gift(p_gift_token text)` anonymously or while authenticated. It returns only:

- `result_code`, `valid`, `gift_status`, and `may_open`;
- Campaign headline, description, and terms when safe.

Result codes are `GIFT_AVAILABLE`, `OPEN_WINDOW_EXPIRED`, `GIFT_OPENED`, `GIFT_UNAVAILABLE`, and `INVALID_GIFT`. Cancelled Gifts expose no cancellation reason or campaign copy. Invalid tokens return the same minimal response whether malformed or unknown.

The public result never contains Bill data, Staff data, database IDs, Prize configuration, probability, inventory, estimated cost, Reward snapshots, or Audit data. Phase 1D does not open Gifts or create Rewards.
