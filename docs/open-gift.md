# Public Gift Opening Contract

Phase 3A exposes `api.open_gift(p_gift_token text)` to anonymous and authenticated callers. The opaque Gift Token is its only Customer-controlled input. Prize IDs, card numbers, random values, Bill data, and Staff identity are never accepted.

## Public response

The function returns only `result_code`, `reward_available`, `reward_status`, `reward_name`, `reward_description`, `reward_type`, `customer_value_vnd`, `minimum_spend_vnd`, `applicable_service`, `discount_percent`, `reward_terms`, `reward_code`, and `reward_expires_at`.

Safe outcomes are `OPENED_NOW`, `ALREADY_OPENED`, `INVALID_GIFT`, `GIFT_CANCELLED`, and `OPEN_WINDOW_EXPIRED`. No internal IDs, Bill/Staff data, Prize weight, cost, inventory, probability, fallback flag, or Audit data is returned.

## Transaction and idempotency

The function locks the issued Campaign Version and then the Gift row. This deliberately serializes openings within one Campaign Version—a simple trade-off for a one-store campaign—and gives every competing request a consistent inventory view. The existing Reward is checked before randomization, so refreshes and concurrent requests return the same Reward without consuming inventory or writing another assignment Audit.

Prize selection, Reward insert, inventory increment, Gift transition to `OPENED`, and the first `OPEN_GIFT` Audit insert share one PostgreSQL transaction. Any failure rolls back all of them.

## Prize and entitlement rules

Only active, non-fallback Prizes with positive relative weight and remaining finite/unlimited inventory enter the weighted pool. Weights need not total 100. The one active unlimited fallback is selected only when no normal Prize remains. A private deterministic selector tests exact weight boundaries; browser roles cannot execute it, and `api.open_gift` supplies its own server-generated random value.

The Reward persists a snapshot of its name, type, description, customer value, discount, minimum spend, applicable service, campaign terms, and expiry rule. The final expiration timestamp and unique `CHIC-…` Reward Code are generated and stored server-side.

Campaign status governs Gift creation, not an entitlement already issued. An eligible Gift remains openable after its Campaign becomes `ENDED` or `ARCHIVED`, subject to its own cancellation and opening deadline.

## Customer presentation (Phase 3B)

An unopened public Gift shows exactly nine equal visual envelopes. They are presentation only: the first selection locks the grid and immediately calls `api.open_gift` with `{ p_gift_token }`. No card position, Prize identifier, random value, Campaign/Reward identifier, or Bill data leaves the browser. Supabase performs and persists the actual selection.

The selected envelope remains locked after a transport failure. **THỬ LẠI** repeats the same token-only, idempotent RPC, so a lost response recovers the existing Reward rather than offering another selection. A QR revisit first uses `get_public_gift`; `GIFT_OPENED` skips the nine envelopes and calls `open_gift` to display the persisted Reward.

The reveal maps only the public response: Reward name and customer benefit, persisted code and expiry, plus non-empty description, service, minimum-spend, discount, and terms fields. No Reward data is stored in browser storage. The mobile-first 3 × 3 controls use semantic buttons, visible focus, live loading/error feedback, and CSS-only motion disabled by `prefers-reduced-motion`.

## Development mobile UAT

Phase 3B passed MUI01–MUI15 on 8 September 2026 using an anonymous phone on trusted local Wi-Fi. The test covered QR entry, nine-card selection and locking, hosted Reward opening, readable code/expiry/conditions, refresh to the same persisted Reward, invalid-token handling, mobile fit, and safe-data-only output. The Development-only Campaign was archived after validation; its published Version, two Prizes, Gift, Reward, and Audit history were retained.
