-- Phase 1D functional and security checks.
-- Run only against an isolated development/test Supabase database after migrations.
-- All fixtures and Audit rows are rolled back.

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
    '81000000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'phase1d-staff@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '81000000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'phase1d-admin@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '81000000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated', 'phase1d-inactive@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '81000000-0000-0000-0000-000000000004',
    'authenticated', 'authenticated', 'phase1d-no-profile@example.invalid', '', now(),
    '{}', '{}', now(), now()
  );

insert into private.staff_profiles (id, branch_id, name, role, active)
values
  (
    '81000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'Phase 1D Staff', 'STAFF', true
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'Phase 1D Admin', 'ADMIN', true
  ),
  (
    '81000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000001',
    'Phase 1D Inactive', 'STAFF', false
  );

insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
values (
  '82000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'Phase 1D Test Campaign',
  'DRAFT',
  statement_timestamp() - interval '1 day',
  statement_timestamp() + interval '30 days',
  '81000000-0000-0000-0000-000000000002'
);

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  gift_open_deadline_hours, headline, description, terms, created_by
)
values (
  '83000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  1,
  200000,
  24,
  'Hôm nay nàng có quà',
  'Chọn một món quà bí mật dành cho nàng.',
  'Áp dụng theo điều kiện của chương trình.',
  '81000000-0000-0000-0000-000000000002'
);

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, expiry_days,
  weight, max_quantity, is_fallback
)
values (
  '84000000-0000-0000-0000-000000000001',
  '83000000-0000-0000-0000-000000000001',
  'Phase 1D Fallback',
  'FREE_SERVICE',
  'Test-only fallback',
  30000,
  7000,
  30,
  1,
  null,
  true
);

update private.campaign_versions
set published_at = statement_timestamp()
where id = '83000000-0000-0000-0000-000000000001';

update private.campaigns
set current_version_id = '83000000-0000-0000-0000-000000000001',
    status = 'ACTIVE'
where id = '82000000-0000-0000-0000-000000000001';

-- CG01: anonymous cannot create.
set local role anon;
select pg_temp.assert_raises(
  $$select * from api.create_gift('CG-ANON', 300000)$$,
  '42501',
  'CG01 Anonymous caller must not create Gift'
);
reset role;

-- CG02: authenticated user without Staff profile cannot create.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000004',
  true
);
select pg_temp.assert_raises(
  $$select * from api.create_gift('CG-NO-PROFILE', 300000)$$,
  '42501',
  'CG02 Authenticated user without Staff profile must not create Gift'
);
reset role;

-- CG03: inactive Staff cannot create.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000003',
  true
);
select pg_temp.assert_raises(
  $$select * from api.create_gift('CG-INACTIVE', 300000)$$,
  '42501',
  'CG03 Inactive Staff must not create Gift'
);
reset role;

-- CG04: active Staff can create.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'CREATED_GIFT' and is_new
   from api.create_gift('CG-STAFF-01', 300000)),
  'CG04 Active Staff must create Gift'
);
reset role;

-- CG05: active Admin can create.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000002',
  true
);
select pg_temp.assert_true(
  (select result_code = 'CREATED_GIFT' and is_new
   from api.create_gift('CG-ADMIN-01', 300000)),
  'CG05 Active Admin must create Gift'
);
reset role;

-- CG06 and CG07: outer whitespace is trimmed and Bill Code is uppercased.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'CREATED_GIFT' and bill_code = 'CG-NORMAL-01'
   from api.create_gift(E'  cg-normal-01\t', 300000)),
  'CG06-CG07 Bill normalization must trim and uppercase'
);
reset role;

-- CG08: internal whitespace is rejected.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'INVALID_BILL_CODE' and gift_id is null
   from api.create_gift('CG INVALID', 300000)),
  'CG08 Internal Bill whitespace must be rejected'
);
reset role;

-- CG09: campaign minimum comes from the Campaign Version.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'BILL_BELOW_MINIMUM'
      and minimum_bill_vnd = 200000
      and gift_id is null
   from api.create_gift('CG-BELOW-01', 199999)),
  'CG09 Bill below configured minimum must be rejected'
);
reset role;

-- CG10: no ACTIVE Campaign prevents creation.
update private.campaigns
set status = 'PAUSED'
where id = '82000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'NO_ACTIVE_CAMPAIGN' and gift_id is null
   from api.create_gift('CG-NO-CAMPAIGN', 300000)),
  'CG10 Missing ACTIVE Campaign must prevent creation'
);
reset role;

-- CG11: ACTIVE Campaign outside its date window prevents creation.
update private.campaigns
set status = 'ACTIVE',
    start_at = statement_timestamp() + interval '1 day',
    end_at = statement_timestamp() + interval '2 days'
where id = '82000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'NO_ACTIVE_CAMPAIGN' and gift_id is null
   from api.create_gift('CG-OUTSIDE-DATE', 300000)),
  'CG11 Campaign date window must be enforced'
);
reset role;

update private.campaigns
set start_at = statement_timestamp() - interval '1 day',
    end_at = statement_timestamp() + interval '30 days'
where id = '82000000-0000-0000-0000-000000000001';

-- CG12-CG14: valid creation, exact version, secure unique token.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'CREATED_GIFT'
      and gift_status = 'ELIGIBLE'
      and gift_token ~ '^[0-9a-f]{64}$'
   from api.create_gift('CG-VALID-01', 385000)),
  'CG12-CG14 Valid Gift must be ELIGIBLE with a secure token'
);
reset role;

select pg_temp.assert_true(
  (
    select count(*) = 1
      and bool_and(status = 'ELIGIBLE')
      and bool_and(
        campaign_version_id = '83000000-0000-0000-0000-000000000001'
      )
    from private.gift_entries
    where bill_code_normalized = 'CG-VALID-01'
  ),
  'CG12-CG13 Gift must exist once and reference exact Campaign Version'
);

select pg_temp.assert_true(
  (
    select count(*) = count(distinct gift_token)
      and bool_and(gift_token ~ '^[0-9a-f]{64}$')
    from private.gift_entries
    where created_by in (
      '81000000-0000-0000-0000-000000000001',
      '81000000-0000-0000-0000-000000000002'
    )
  ),
  'CG14 Generated Gift Tokens must be secure and unique'
);

select set_config(
  'chic_gift.phase_1d_token',
  (
    select gift_token
    from private.gift_entries
    where bill_code_normalized = 'CG-VALID-01'
  ),
  true
);

-- CG15: normalized duplicate with same amount returns existing Gift.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'EXISTING_GIFT'
      and not is_new
      and gift_token = current_setting('chic_gift.phase_1d_token')
   from api.create_gift('  cg-valid-01 ', 385000)),
  'CG15 Same normalized Bill and amount must return existing Gift'
);
reset role;

-- CG16: duplicate with another amount is rejected without changing stored data.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '81000000-0000-0000-0000-000000000001',
  true
);
select pg_temp.assert_true(
  (select result_code = 'AMOUNT_MISMATCH'
      and not is_new
      and gift_token is null
      and bill_amount_vnd = 385000
   from api.create_gift('CG-VALID-01', 485000)),
  'CG16 Amount mismatch must preserve the existing Gift and withhold its token'
);
reset role;

select pg_temp.assert_true(
  (
    select count(*) = 1 and bool_and(bill_amount_vnd = 385000)
    from private.gift_entries
    where bill_code_normalized = 'CG-VALID-01'
  ),
  'CG16 Amount mismatch must not update or duplicate Gift'
);

-- CG17 has a separate true multi-session remote test. This verifies idempotence too.
select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.gift_entries
    where bill_code_normalized = 'CG-VALID-01'
  ),
  'CG17 Repeated same-Bill calls must leave one Gift row'
);

-- CG18-CG20: trusted operation writes required Audit events.
select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.audit_logs
    where action = 'CREATE_GIFT'
      and bill_code_normalized = 'CG-VALID-01'
  ),
  'CG18 CREATE_GIFT Audit must be generated'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.audit_logs
    where action = 'DUPLICATE_ATTEMPT'
      and bill_code_normalized = 'CG-VALID-01'
  ),
  'CG19 DUPLICATE_ATTEMPT Audit must be generated'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.audit_logs
    where action = 'AMOUNT_MISMATCH'
      and bill_code_normalized = 'CG-VALID-01'
  ),
  'CG20 AMOUNT_MISMATCH Audit must be generated'
);

-- Public fixtures for cancelled and expired opening-window behavior.
insert into private.gift_entries (
  id, branch_id, bill_code_entered, bill_amount_vnd,
  campaign_version_id, gift_token, status, open_expires_at,
  created_by, cancelled_at, cancelled_by
)
values (
  '85000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'PG-CANCELLED-01',
  300000,
  '83000000-0000-0000-0000-000000000001',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  'CANCELLED',
  null,
  '81000000-0000-0000-0000-000000000001',
  statement_timestamp(),
  '81000000-0000-0000-0000-000000000002'
), (
  '85000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  'PG-EXPIRED-01',
  300000,
  '83000000-0000-0000-0000-000000000001',
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  'ELIGIBLE',
  statement_timestamp() - interval '1 minute',
  '81000000-0000-0000-0000-000000000001',
  null,
  null
);

-- PG01-PG08: anonymous lookup returns only the customer-safe projection.
set local role anon;
select pg_temp.assert_true(
  (
    select result_code = 'GIFT_AVAILABLE'
      and valid
      and gift_status = 'ELIGIBLE'
      and may_open
      and campaign_headline = 'Hôm nay nàng có quà'
    from api.get_public_gift(current_setting('chic_gift.phase_1d_token'))
  ),
  'PG01 Valid ELIGIBLE token must return customer-safe payload'
);

select pg_temp.assert_true(
  (
    select result_code = 'INVALID_GIFT'
      and not valid
      and gift_status is null
      and not may_open
    from api.get_public_gift('not-a-real-token-not-a-real-token-0001')
  ),
  'PG02 Invalid token must return safe response'
);

select pg_temp.assert_true(
  (
    select not (
      to_jsonb(public_gift) ?| array[
        'bill_code',
        'bill_amount',
        'bill_amount_vnd',
        'gift_id',
        'staff',
        'staff_id',
        'created_by',
        'campaign_id',
        'campaign_version_id',
        'prize',
        'prizes',
        'prize_id',
        'prize_weight',
        'weight',
        'inventory',
        'max_quantity',
        'issued_quantity',
        'estimated_chic_cost_vnd',
        'audit',
        'audit_data',
        'audit_logs'
      ]
    )
    from api.get_public_gift(current_setting('chic_gift.phase_1d_token')) as public_gift
  ),
  'PG03-PG08 Public payload must omit Bill, Staff, Prize, cost, and Audit internals'
);

select pg_temp.assert_raises(
  $$select * from private.gift_entries$$,
  '42501',
  'PG09 Anonymous caller must not SELECT internal Gift table'
);

select pg_temp.assert_true(
  (
    select result_code = 'GIFT_UNAVAILABLE'
      and valid
      and gift_status = 'CANCELLED'
      and not may_open
      and campaign_headline is null
    from api.get_public_gift(
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    )
  ),
  'PG10 Cancelled Gift must return safe unavailable response'
);

select pg_temp.assert_true(
  (
    select result_code = 'OPEN_WINDOW_EXPIRED'
      and valid
      and gift_status = 'ELIGIBLE'
      and not may_open
    from api.get_public_gift(
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    )
  ),
  'PG11 Gift opening deadline must disable opening'
);
reset role;

rollback;
