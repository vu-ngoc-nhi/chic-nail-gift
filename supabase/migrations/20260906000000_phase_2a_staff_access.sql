-- CHIC GIFT Phase 2A: minimal authorization check for the Staff application.
-- Authentication remains in Supabase Auth; this function discloses no Staff records.

create or replace function api.get_staff_access()
returns table (
  authorized boolean,
  staff_role text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    true as authorized,
    sp.role::text as staff_role
  from private.staff_profiles as sp
  join private.branches as b on b.id = sp.branch_id
  where sp.id = (select auth.uid())
    and sp.active
    and b.active
    and sp.role in ('STAFF', 'ADMIN');
$$;

comment on function api.get_staff_access() is
  'Confirms whether the signed-in user may enter the Staff application.';

revoke all on function api.get_staff_access()
  from public, anon, authenticated, service_role;

grant execute on function api.get_staff_access() to authenticated;
