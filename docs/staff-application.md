# Staff Application

Phase 2A provides the minimum authenticated workflow at `/login` and `/staff`. It does not include QR display, Customer pages, Reward opening, redemption, or Admin screens.

## Local configuration

Copy `.env.example` to `.env.local`, then fill in only:

- `VITE_SUPABASE_URL` — the Development project URL.
- `VITE_SUPABASE_PUBLISHABLE_KEY` — the browser-safe publishable key.
- `VITE_PUBLIC_APP_URL` — optional public application origin used to build `/g/{giftToken}` links. When blank, the current browser origin is used.

Never place a Secret Key, Service Role key, database password, or Personal Access Token in a `VITE_` variable. `.env.local` is ignored by Git.

## Authorization flow

Supabase Auth restores the email/password session. The application then calls `api.get_staff_access`; only an active `STAFF` or `ADMIN` profile on an active branch may enter the Staff screen. Unauthorized sessions are cleared locally. Gift creation calls only `api.create_gift`; the browser never reads or writes `private` tables.

## Development Staff account

For manual UAT, create a user in **Supabase Dashboard → Authentication → Users** for the Development project. Keep its password private. Then insert a matching `private.staff_profiles` row whose `id` equals the Auth user ID, uses the development branch ID, has role `STAFF` or `ADMIN`, and has `active = true`. Do not create this account in production during Phase 2A.
