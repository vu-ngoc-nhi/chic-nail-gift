# Staff Reward Redemption

Phase 4A adds a Staff-only reward lookup and one-way redemption workflow. KiotViet remains the sales source of truth: Staff must manually verify the redemption bill, applicable service, and reward terms before confirming.

## API contract

- `api.get_reward_for_redemption(p_reward_code text)` returns only operational snapshot fields, expiry, status, and safe redemption metadata for the Staff member's branch.
- `api.redeem_reward(p_reward_code text, p_redemption_bill_code text, p_redemption_bill_amount_vnd bigint, p_conditions_confirmed boolean)` performs the final validation and transition.

Both functions require an authenticated, active Staff/Admin profile on an active branch. Browser roles retain no direct access to `private` tables.

## Transaction guarantees

`redeem_reward` normalizes the bill code, locks the Reward row, and validates cancellation, prior redemption, server-time expiry, branch ownership, confirmation, and minimum spend. A successful call writes normalized redemption Bill metadata, server-generated `redeemed_at`, server-resolved `redeemed_by`, and one append-only `REDEEM_GIFT` Audit event in the same transaction.

Concurrent or repeated calls cannot replace the first successful redemption metadata. Losing calls return `ALREADY_REDEEMED`.

## Store workflow

1. Open `/staff/redeem` and enter the customer's Reward Code.
2. Review benefit, expiry, applicable service, minimum spend, and terms.
3. Verify the current bill and service directly in KiotViet.
4. Enter the redemption Bill Code and integer VND amount.
5. Confirm the manual checks, then select **XÁC NHẬN ĐÃ SỬ DỤNG QUÀ**.

Applicable service is intentionally not validated automatically because Phase 4A has no KiotViet service-catalog integration.

## Development validation

Use only labeled Development fixtures. Retain immutable Campaign/Version/Prize/Audit history according to the approved cleanup policy; archive the Development Campaign after UAT. Never use a real customer bill or production data.
