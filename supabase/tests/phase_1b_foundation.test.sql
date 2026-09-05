-- Phase 1B database checks.
-- Run only against an isolated development/test Supabase database after migrations.
-- The transaction is rolled back, so fixtures are never retained.

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

select pg_temp.assert_true(
  private.normalize_bill_code(E'  HD00123\t') = 'HD00123',
  'Bill normalization must trim outer whitespace'
);

select pg_temp.assert_true(
  private.normalize_bill_code('hd00123') = 'HD00123',
  'Bill normalization must uppercase Bill Code'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
      and bool_and(id = '00000000-0000-0000-0000-000000000001'::uuid)
      and bool_and(name = 'Chic Nail & Beauty — Development')
    from private.branches
    where code = 'CHIC-DEV'
  ),
  'Development seed must contain exactly the approved CHIC-DEV branch'
);

select pg_temp.assert_true(
  (
    select count(*) = 8
    from pg_catalog.pg_class as c
    join pg_catalog.pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'private'
      and c.relkind = 'r'
      and c.relrowsecurity
  ),
  'RLS must be enabled on all eight private application tables'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'private'
      and grantee in ('PUBLIC', 'anon', 'authenticated')
  ),
  'Browser roles must have no direct grants on private application tables'
);

select pg_temp.assert_raises(
  $$select private.normalize_bill_code('HD 00123')$$,
  '23514',
  'Bill normalization must reject internal whitespace'
);

insert into private.branches (id, code, name)
values (
  '10000000-0000-0000-0000-000000000001',
  'TEST-BRANCH',
  'Phase 1B Test Branch'
);

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'phase1b-staff@example.invalid',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '20000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'phase1b-admin@example.invalid',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  );

insert into private.staff_profiles (id, branch_id, name, role)
values
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Test Staff',
    'STAFF'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'Test Admin',
    'ADMIN'
  );

insert into private.campaigns (
  id,
  branch_id,
  name,
  start_at,
  end_at,
  created_by
)
values (
  '30000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Test Campaign One',
  now() - interval '1 day',
  now() + interval '30 days',
  '20000000-0000-0000-0000-000000000002'
);

insert into private.campaign_versions (
  id,
  campaign_id,
  version_number,
  min_bill_vnd,
  gift_open_deadline_hours,
  headline,
  description,
  terms,
  created_by
)
values (
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  1,
  200000,
  24,
  'Test headline',
  'Test description',
  'Test terms',
  '20000000-0000-0000-0000-000000000002'
);

insert into private.prizes (
  id,
  campaign_version_id,
  name,
  type,
  customer_description,
  customer_value_vnd,
  estimated_chic_cost_vnd,
  minimum_spend_vnd,
  expiry_days,
  weight,
  max_quantity,
  is_fallback
)
values
  (
    '50000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    'Normal Test Prize',
    'CASH_VOUCHER',
    'Normal test prize',
    50000,
    10000,
    200000,
    30,
    10,
    1,
    false
  ),
  (
    '50000000-0000-0000-0000-000000000002',
    '40000000-0000-0000-0000-000000000001',
    'Fallback Test Prize',
    'FREE_SERVICE',
    'Fallback test prize',
    30000,
    7000,
    0,
    30,
    1,
    null,
    true
  );

update private.campaign_versions
set published_at = now()
where id = '40000000-0000-0000-0000-000000000001';

update private.campaigns
set current_version_id = '40000000-0000-0000-0000-000000000001',
    status = 'ACTIVE'
where id = '30000000-0000-0000-0000-000000000001';

insert into private.gift_entries (
  id,
  branch_id,
  bill_code_entered,
  bill_amount_vnd,
  campaign_version_id,
  gift_token,
  created_by
)
values
  (
    '60000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'hd00123',
    300000,
    '40000000-0000-0000-0000-000000000001',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    '20000000-0000-0000-0000-000000000001'
  ),
  (
    '60000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000001',
    'HD00124',
    300000,
    '40000000-0000-0000-0000-000000000001',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    '20000000-0000-0000-0000-000000000001'
  );

select pg_temp.assert_true(
  (
    select bill_code_normalized
    from private.gift_entries
    where id = '60000000-0000-0000-0000-000000000001'
  ) = 'HD00123',
  'Stored Bill Code must use database normalization'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.gift_entries (
      branch_id, bill_code_entered, bill_amount_vnd,
      campaign_version_id, gift_token, created_by
    ) values (
      '10000000-0000-0000-0000-000000000001', ' HD00123 ', 300000,
      '40000000-0000-0000-0000-000000000001',
      'ccccccccccccccccccccccccccccccccccccccccccc',
      '20000000-0000-0000-0000-000000000001'
    )
  $sql$,
  '23505',
  'Duplicate normalized Bill Code per branch must fail'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.gift_entries (
      branch_id, bill_code_entered, bill_amount_vnd,
      campaign_version_id, gift_token, created_by
    ) values (
      '10000000-0000-0000-0000-000000000001', 'HD00125', 300000,
      '40000000-0000-0000-0000-000000000001',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      '20000000-0000-0000-0000-000000000001'
    )
  $sql$,
  '23505',
  'Gift Token must be unique'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.gift_entries (
      branch_id, bill_code_entered, bill_amount_vnd,
      campaign_version_id, gift_token, created_by
    ) values (
      '10000000-0000-0000-0000-000000000001', 'HD00126', -1,
      '40000000-0000-0000-0000-000000000001',
      'ddddddddddddddddddddddddddddddddddddddddddd',
      '20000000-0000-0000-0000-000000000001'
    )
  $sql$,
  '23514',
  'Negative Bill Amount must fail'
);

insert into private.rewards (
  id,
  gift_entry_id,
  prize_id,
  reward_code,
  prize_snapshot,
  expires_at
)
values (
  '70000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  'CHIC-TEST01',
  '{"name":"Normal Test Prize","customer_value_vnd":50000}',
  now() + interval '30 days'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.rewards (
      gift_entry_id, prize_id, reward_code, prize_snapshot, expires_at
    ) values (
      '60000000-0000-0000-0000-000000000001',
      '50000000-0000-0000-0000-000000000001',
      'CHIC-TEST02', '{}', now() + interval '30 days'
    )
  $sql$,
  '23505',
  'A Gift Entry must have at most one Reward'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.rewards (
      gift_entry_id, prize_id, reward_code, prize_snapshot, expires_at
    ) values (
      '60000000-0000-0000-0000-000000000002',
      '50000000-0000-0000-0000-000000000001',
      'CHIC-TEST01', '{}', now() + interval '30 days'
    )
  $sql$,
  '23505',
  'Reward Code must be unique'
);

insert into private.campaigns (
  id, branch_id, name, start_at, end_at, created_by
)
values (
  '30000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000001',
  'Test Campaign Two',
  now() - interval '1 day',
  now() + interval '30 days',
  '20000000-0000-0000-0000-000000000002'
);

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  headline, description, terms, created_by
)
values (
  '40000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000002',
  1,
  200000,
  'Second headline',
  'Second description',
  'Second terms',
  '20000000-0000-0000-0000-000000000002'
);

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, expiry_days,
  weight, is_fallback
)
values (
  '50000000-0000-0000-0000-000000000003',
  '40000000-0000-0000-0000-000000000002',
  'Second Fallback',
  'FREE_SERVICE',
  'Second fallback',
  30000,
  7000,
  30,
  1,
  true
);

update private.campaign_versions
set published_at = now()
where id = '40000000-0000-0000-0000-000000000002';

update private.campaigns
set current_version_id = '40000000-0000-0000-0000-000000000002'
where id = '30000000-0000-0000-0000-000000000002';

select pg_temp.assert_raises(
  $$
    update private.campaigns
    set status = 'ACTIVE'
    where id = '30000000-0000-0000-0000-000000000002'
  $$,
  '23505',
  'Only one ACTIVE Campaign per branch is allowed'
);

select pg_temp.assert_raises(
  $$
    update private.campaign_versions
    set headline = 'Changed history'
    where id = '40000000-0000-0000-0000-000000000001'
  $$,
  'P0001',
  'Published Campaign Version must be immutable'
);

select pg_temp.assert_raises(
  $$
    update private.prizes
    set customer_value_vnd = 1
    where id = '50000000-0000-0000-0000-000000000001'
  $$,
  'P0001',
  'Prize attached to published Campaign Version must be immutable'
);

update private.prizes
set issued_quantity = issued_quantity + 1
where id = '50000000-0000-0000-0000-000000000001';

select pg_temp.assert_true(
  (
    select issued_quantity
    from private.prizes
    where id = '50000000-0000-0000-0000-000000000001'
  ) = 1,
  'Published Prize inventory counter must be allowed to increase'
);

select pg_temp.assert_raises(
  $$
    update private.prizes
    set issued_quantity = issued_quantity + 1
    where id = '50000000-0000-0000-0000-000000000001'
  $$,
  '23514',
  'Published Prize inventory must not exceed max quantity'
);

insert into private.campaigns (
  id, branch_id, name, start_at, end_at, created_by
)
values (
  '30000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000001',
  'Test Campaign Three',
  now() - interval '1 day',
  now() + interval '30 days',
  '20000000-0000-0000-0000-000000000002'
);

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  headline, description, terms, created_by
)
values (
  '40000000-0000-0000-0000-000000000003',
  '30000000-0000-0000-0000-000000000003',
  1,
  200000,
  'Third headline',
  'Third description',
  'Third terms',
  '20000000-0000-0000-0000-000000000002'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.campaign_versions (
      campaign_id, version_number, min_bill_vnd,
      headline, description, terms, created_by
    ) values (
      '30000000-0000-0000-0000-000000000003', 2, -1,
      'Invalid minimum', 'Invalid minimum', 'Invalid minimum',
      '20000000-0000-0000-0000-000000000002'
    )
  $sql$,
  '23514',
  'Negative Campaign minimum Bill must fail'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.campaign_versions (
      campaign_id, version_number, min_bill_vnd,
      headline, description, terms, published_at, created_by
    ) values (
      '30000000-0000-0000-0000-000000000003', 2, 200000,
      'Invalid direct publication', 'Invalid direct publication',
      'Invalid direct publication', now(),
      '20000000-0000-0000-0000-000000000002'
    )
  $sql$,
  '23514',
  'Direct publication without an active unlimited fallback must fail'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.prizes (
      campaign_version_id, name, type, customer_description,
      customer_value_vnd, estimated_chic_cost_vnd, minimum_spend_vnd,
      expiry_days, weight
    ) values (
      '40000000-0000-0000-0000-000000000003',
      'Invalid Cost', 'FREE_SERVICE', 'Invalid negative cost',
      -1, -1, -1, 30, 1
    )
  $sql$,
  '23514',
  'Negative Prize VND values must fail'
);

select pg_temp.assert_raises(
  $$
    update private.campaign_versions
    set published_at = now()
    where id = '40000000-0000-0000-0000-000000000003'
  $$,
  '23514',
  'Publishing without one active unlimited fallback must fail'
);

select pg_temp.assert_raises(
  $sql$
    insert into private.prizes (
      campaign_version_id, name, type, customer_description,
      customer_value_vnd, estimated_chic_cost_vnd, expiry_days,
      weight, max_quantity, is_fallback
    ) values (
      '40000000-0000-0000-0000-000000000003',
      'Finite Fallback', 'FREE_SERVICE', 'Invalid finite fallback',
      30000, 7000, 30, 1, 10, true
    )
  $sql$,
  '23514',
  'Fallback Prize must have unlimited inventory'
);

insert into private.audit_logs (
  action,
  actor_id,
  actor_role,
  branch_id,
  entity_type,
  entity_id
)
values (
  'LOGIN',
  '20000000-0000-0000-0000-000000000001',
  'STAFF',
  '10000000-0000-0000-0000-000000000001',
  'AUTH',
  '20000000-0000-0000-0000-000000000001'
);

select pg_temp.assert_raises(
  $$update private.audit_logs set action = 'CREATE_GIFT'$$,
  'P0001',
  'Audit UPDATE must fail even for the database owner'
);

select pg_temp.assert_raises(
  $$delete from private.audit_logs$$,
  'P0001',
  'Audit DELETE must fail even for the database owner'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  private.is_active_staff(),
  'Active Staff profile must pass Staff helper'
);
select pg_temp.assert_true(
  not private.is_active_admin(),
  'Staff profile must not pass Admin helper'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000002',
  true
);
select pg_temp.assert_true(
  private.is_active_staff() and private.is_active_admin(),
  'Active Admin must pass both role helpers'
);
select pg_temp.assert_raises(
  $$select * from private.gift_entries$$,
  '42501',
  'Authenticated users must not have broad table access'
);
select pg_temp.assert_raises(
  $$update private.audit_logs set action = 'CREATE_GIFT'$$,
  '42501',
  'Authenticated application roles must not update Audit Logs'
);
select pg_temp.assert_raises(
  $$delete from private.audit_logs$$,
  '42501',
  'Authenticated application roles must not delete Audit Logs'
);
reset role;

set local role anon;
select pg_temp.assert_raises(
  $$select * from private.gift_entries$$,
  '42501',
  'Anonymous users must not have broad table access'
);
select pg_temp.assert_raises(
  $$insert into private.branches (code, name) values ('ANON-TEST', 'Anonymous Test')$$,
  '42501',
  'Anonymous users must not have broad table write access'
);
reset role;

update private.staff_profiles
set active = false
where id = '20000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '20000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  not private.is_active_staff(),
  'Inactive Staff must fail authorization helper'
);
reset role;

rollback;
