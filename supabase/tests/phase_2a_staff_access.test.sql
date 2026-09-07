-- Phase 2A Staff access authorization checks.
-- Run only against an isolated development/test database. All fixtures roll back.

begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(p_condition, false) then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;

create or replace function pg_temp.assert_raises(
  p_statement text,
  p_expected_state text,
  p_message text
)
returns void
language plpgsql
as $$
declare
  v_state text;
begin
  begin
    execute p_statement;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state = p_expected_state then
      return;
    end if;
    raise exception 'ASSERTION FAILED: % (expected SQLSTATE %, received %)',
      p_message,
      p_expected_state,
      v_state;
  end;

  raise exception 'ASSERTION FAILED: % (statement did not fail)', p_message;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'phase2a-staff@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'phase2a-admin@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated', 'phase2a-inactive@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'a1000000-0000-0000-0000-000000000004',
    'authenticated', 'authenticated', 'phase2a-no-profile@example.invalid', '', now(),
    '{}', '{}', now(), now()
  );

insert into private.staff_profiles (id, branch_id, name, role, active)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'Phase 2A Staff', 'STAFF', true
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'Phase 2A Admin', 'ADMIN', true
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000001',
    'Phase 2A Inactive', 'STAFF', false
  );

-- SA04/SA05: anonymous, no-profile, and inactive users are denied.
set local role anon;
select pg_temp.assert_raises(
  $$select * from api.get_staff_access()$$,
  '42501',
  'Anonymous must not execute the Staff access check'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-0000-0000-000000000004',
  true
);
select pg_temp.assert_true(
  not exists (select from api.get_staff_access()),
  'Authenticated user without a Staff profile must be denied'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-0000-0000-000000000003',
  true
);
select pg_temp.assert_true(
  not exists (select from api.get_staff_access()),
  'Inactive Staff must be denied'
);
reset role;

-- SA03: active Staff and Admin are recognized without exposing profile rows.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (
    select authorized and staff_role = 'STAFF'
    from api.get_staff_access()
  ),
  'Active Staff must be authorized'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-0000-0000-000000000002',
  true
);
select pg_temp.assert_true(
  (
    select authorized and staff_role = 'ADMIN'
    from api.get_staff_access()
  ),
  'Active Admin must be authorized'
);
reset role;

rollback;
