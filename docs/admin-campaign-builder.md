# Phase 5A — Admin Campaign Builder

The protected `/admin/campaigns` workspace lets an active `ADMIN` configure a complete campaign without direct SQL. Ordinary `STAFF` users do not see the Admin navigation and are redirected away from the route.

## Operating workflow

1. Create a Draft with campaign dates and customer-facing Version content.
2. Add at least one active normal Prize. Weights are relative and do not need to total 100.
3. Add exactly one active fallback Prize with unlimited inventory.
4. Review the validation summary, then publish the Version deliberately.
5. Activate separately after confirming the campaign is within its date window and no other campaign is active for the branch.
6. Pause, resume, end, and archive through explicit lifecycle controls.

Published Version and Prize configuration is read-only. To change it, pause the campaign and use **Tạo phiên bản mới**. The server clones the current configuration into a new unpublished Version, resets issued quantities, and preserves the previous Version unchanged.

## Security and data handling

The browser calls only Admin-specific functions in the `api` schema. Every function resolves the actor, active `ADMIN` role, and branch from authenticated server context. Internal tables remain inaccessible to browser roles; no Service Role key is required.

“Giá trị khách nhận” and “Chi phí dự kiến của Chic” are separate. Internal cost appears only in the Admin response/UI and is absent from customer Gift and Reward APIs. Meaningful create, edit, publish, and lifecycle operations append Audit events.

## Validation

The database remains authoritative for date ordering, Prize fields, fallback inventory, publication, one active campaign per branch, immutable history, and server-owned actor identity.

Run the isolated backend test against local Supabase:

```sh
psql "$LOCAL_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/tests/phase_5a_admin_campaign_builder.test.sql
```

Run frontend and regression checks with `npm test`, `npm run build`, and `npm run lint`.
