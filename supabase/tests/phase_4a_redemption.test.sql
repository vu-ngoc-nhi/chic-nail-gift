-- Phase 4A Staff lookup and atomic redemption checks.
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
      p_message, p_expected_state, v_state;
  end;
  raise exception 'ASSERTION FAILED: % (statement did not fail)', p_message;
end;
$$;

insert into private.branches (id, code, name)
values
  ('d1000000-0000-0000-0000-000000000001', 'PHASE-4A-A', 'Phase 4A Branch A'),
  ('d1000000-0000-0000-0000-000000000002', 'PHASE-4A-B', 'Phase 4A Branch B');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    'd1100000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'phase4a-staff-a@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'd1100000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'phase4a-staff-b@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'd1100000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated', 'phase4a-inactive@example.invalid', '', now(),
    '{}', '{}', now(), now()
  );

insert into private.staff_profiles (id, branch_id, name, role, active)
values
  (
    'd1100000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'Phase 4A Staff A', 'STAFF', true
  ),
  (
    'd1100000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000002',
    'Phase 4A Staff B', 'STAFF', true
  ),
  (
    'd1100000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000001',
    'Phase 4A Inactive Staff', 'STAFF', false
  );

insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
values
  (
    'd2000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'Phase 4A Campaign A', 'DRAFT', now() - interval '1 day', now() + interval '30 days',
    'd1100000-0000-0000-0000-000000000001'
  ),
  (
    'd2000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000002',
    'Phase 4A Campaign B', 'DRAFT', now() - interval '1 day', now() + interval '30 days',
    'd1100000-0000-0000-0000-000000000002'
  );

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd, headline, description, terms, created_by
)
values
  (
    'd3000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000001',
    1, 0, 'Phase 4A A', 'Development test only.', 'Điều kiện Phase 4A.',
    'd1100000-0000-0000-0000-000000000001'
  ),
  (
    'd3000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000002',
    1, 0, 'Phase 4A B', 'Development test only.', 'Điều kiện Phase 4A.',
    'd1100000-0000-0000-0000-000000000002'
  );

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, minimum_spend_vnd,
  applicable_service, expiry_days, weight, is_fallback, active
)
values
  (
    'd4000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000001',
    'Phase 4A Nail Care', 'FREE_SERVICE', 'Tặng chăm sóc móng cơ bản.',
    100000, 20000, 300000, 'Dịch vụ nail', 30, 1, true, true
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000002',
    'Phase 4A Branch B Prize', 'CUSTOM_REWARD', 'Quà chi nhánh B.',
    50000, 10000, 0, null, 30, 1, true, true
  );

insert into private.gift_entries (
  id, branch_id, bill_code_entered, bill_amount_vnd, campaign_version_id,
  gift_token, status, created_by, opened_at, cancelled_at, cancelled_by
)
values
  (
    'd5000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001', 'P4A-SOURCE-1', 400000,
    'd3000000-0000-0000-0000-000000000001', repeat('1', 64), 'OPENED',
    'd1100000-0000-0000-0000-000000000001', now() - interval '1 day', null, null
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000001', 'P4A-SOURCE-2', 400000,
    'd3000000-0000-0000-0000-000000000001', repeat('2', 64), 'OPENED',
    'd1100000-0000-0000-0000-000000000001', now() - interval '10 days', null, null
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000001', 'P4A-SOURCE-3', 400000,
    'd3000000-0000-0000-0000-000000000001', repeat('3', 64), 'CANCELLED',
    'd1100000-0000-0000-0000-000000000001', now() - interval '2 days', now() - interval '1 day',
    'd1100000-0000-0000-0000-000000000001'
  ),
  (
    'd5000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000001', 'P4A-SOURCE-4', 400000,
    'd3000000-0000-0000-0000-000000000001', repeat('4', 64), 'OPENED',
    'd1100000-0000-0000-0000-000000000001', now() - interval '1 day', null, null
  ),
  (
    'd5000000-0000-0000-0000-000000000005',
    'd1000000-0000-0000-0000-000000000001', 'P4A-SOURCE-5', 400000,
    'd3000000-0000-0000-0000-000000000001', repeat('5', 64), 'OPENED',
    'd1100000-0000-0000-0000-000000000001', now() - interval '1 day', null, null
  ),
  (
    'd5000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000002', 'P4A-SOURCE-6', 400000,
    'd3000000-0000-0000-0000-000000000002', repeat('6', 64), 'OPENED',
    'd1100000-0000-0000-0000-000000000002', now() - interval '1 day', null, null
  ),
  (
    'd5000000-0000-0000-0000-000000000007',
    'd1000000-0000-0000-0000-000000000001', 'P4A-SOURCE-7', 400000,
    'd3000000-0000-0000-0000-000000000001', repeat('7', 64), 'OPENED',
    'd1100000-0000-0000-0000-000000000001', now() - interval '1 day', null, null
  );

insert into private.rewards (
  id, gift_entry_id, prize_id, reward_code, prize_snapshot, created_at, expires_at
)
values
  (
    'd6000000-0000-0000-0000-000000000001',
    'd5000000-0000-0000-0000-000000000001', 'd4000000-0000-0000-0000-000000000001',
    'CHIC-RD4A1',
    '{"name":"Phase 4A Nail Care","type":"FREE_SERVICE","customer_description":"Tặng chăm sóc móng cơ bản.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":"Dịch vụ nail","campaign_terms":"Điều kiện Phase 4A.","expiry_days":30}',
    now() - interval '1 day', now() + interval '29 days'
  ),
  (
    'd6000000-0000-0000-0000-000000000002',
    'd5000000-0000-0000-0000-000000000002', 'd4000000-0000-0000-0000-000000000001',
    'CHIC-RD4A2',
    '{"name":"Expired","type":"FREE_SERVICE","customer_description":"Expired.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":"Dịch vụ nail","campaign_terms":"Test.","expiry_days":7}',
    now() - interval '10 days', now() - interval '3 days'
  ),
  (
    'd6000000-0000-0000-0000-000000000003',
    'd5000000-0000-0000-0000-000000000003', 'd4000000-0000-0000-0000-000000000001',
    'CHIC-RD4A3',
    '{"name":"Cancelled","type":"FREE_SERVICE","customer_description":"Cancelled.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":"Dịch vụ nail","campaign_terms":"Test.","expiry_days":30}',
    now() - interval '2 days', now() + interval '28 days'
  ),
  (
    'd6000000-0000-0000-0000-000000000004',
    'd5000000-0000-0000-0000-000000000004', 'd4000000-0000-0000-0000-000000000001',
    'CHIC-RD4A4',
    '{"name":"Equal Minimum","type":"FREE_SERVICE","customer_description":"Equal.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":"Dịch vụ nail","campaign_terms":"Test.","expiry_days":30}',
    now() - interval '1 day', now() + interval '29 days'
  ),
  (
    'd6000000-0000-0000-0000-000000000005',
    'd5000000-0000-0000-0000-000000000005', 'd4000000-0000-0000-0000-000000000001',
    'CHIC-RD4A5',
    '{"name":"Above Minimum","type":"FREE_SERVICE","customer_description":"Above.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":"Dịch vụ nail","campaign_terms":"Test.","expiry_days":30}',
    now() - interval '1 day', now() + interval '29 days'
  ),
  (
    'd6000000-0000-0000-0000-000000000006',
    'd5000000-0000-0000-0000-000000000006', 'd4000000-0000-0000-0000-000000000002',
    'CHIC-RD4A6',
    '{"name":"Wrong Branch","type":"CUSTOM_REWARD","customer_description":"Branch B.","customer_value_vnd":50000,"discount_percent":null,"minimum_spend_vnd":0,"applicable_service":null,"campaign_terms":"Test.","expiry_days":30}',
    now() - interval '1 day', now() + interval '29 days'
  ),
  (
    'd6000000-0000-0000-0000-000000000007',
    'd5000000-0000-0000-0000-000000000007', 'd4000000-0000-0000-0000-000000000001',
    'CHIC-RD4A7',
    '{"name":"Atomic Failure","type":"FREE_SERVICE","customer_description":"Failure.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":0,"applicable_service":"Dịch vụ nail","campaign_terms":"Test.","expiry_days":30}',
    now() - interval '1 day', now() + interval '29 days'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);

-- RD01: unknown Reward Code cannot redeem.
select pg_temp.assert_true(
  (select result_code = 'REWARD_NOT_FOUND' and reward_code is null
   from api.redeem_reward('CHIC-NONE0', 'RD4A-BILL-0', 300000, true)),
  'RD01 Unknown Reward Code must not redeem'
);

-- RD02: available Reward lookup returns operational data.
select pg_temp.assert_true(
  (select result_code = 'REWARD_AVAILABLE' and redeemable and reward_name is not null
   from api.get_reward_for_redemption(' chic-rd4a1 ')),
  'RD02 Available Reward must be found by normalized code'
);

-- RD03: valid Reward redeems successfully.
select pg_temp.assert_true(
  (select result_code = 'REDEEMED' and reward_status = 'REDEEMED'
   from api.redeem_reward('chic-rd4a1', E'  rd4a-bill-1\t', 300000, true)),
  'RD03 Valid Reward must redeem successfully'
);
reset role;

-- RD04-RD09: persisted state, server identity/time, Bill metadata, and one Audit.
select pg_temp.assert_true(
  (select redeemed_at is not null from private.rewards where id = 'd6000000-0000-0000-0000-000000000001'),
  'RD04-RD05 Reward must persist REDEEMED through server-generated redeemed_at'
);
select pg_temp.assert_true(
  (select redeemed_by = 'd1100000-0000-0000-0000-000000000001'
   from private.rewards where id = 'd6000000-0000-0000-0000-000000000001'),
  'RD06 redeemed_by must come from authenticated Staff'
);
select pg_temp.assert_true(
  (select redemption_bill_code = 'RD4A-BILL-1'
      and redemption_bill_amount_vnd = 300000
   from private.rewards where id = 'd6000000-0000-0000-0000-000000000001'),
  'RD07-RD08 normalized Bill Code and integer VND amount must persist'
);
select pg_temp.assert_true(
  (select count(*) = 1
   from private.audit_logs
   where action = 'REDEEM_GIFT' and entity_id = 'd6000000-0000-0000-0000-000000000001'),
  'RD09 Successful redemption must write exactly one Audit event'
);

select set_config(
  'chic_gift.phase_4a_redeemed_at',
  (select redeemed_at::text from private.rewards where id = 'd6000000-0000-0000-0000-000000000001'),
  true
);

-- RD10-RD11: second redemption is stable and safe.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true(
  (select result_code = 'ALREADY_REDEEMED'
      and redemption_bill_code = 'RD4A-BILL-1'
   from api.redeem_reward('CHIC-RD4A1', 'RD4A-DIFFERENT', 999999, true)),
  'RD11 Second redemption must return ALREADY_REDEEMED'
);
reset role;
select pg_temp.assert_true(
  (select redeemed_at::text = current_setting('chic_gift.phase_4a_redeemed_at')
      and redeemed_by = 'd1100000-0000-0000-0000-000000000001'
      and redemption_bill_code = 'RD4A-BILL-1'
      and redemption_bill_amount_vnd = 300000
   from private.rewards where id = 'd6000000-0000-0000-0000-000000000001'),
  'RD10 Second redemption must not change original metadata'
);

-- RD12-RD16: expiry, cancellation, and minimum-spend boundaries.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true(
  (select result_code = 'REWARD_EXPIRED'
   from api.redeem_reward('CHIC-RD4A2', 'RD4A-EXP', 300000, true)),
  'RD12 Expired Reward must not redeem'
);
select pg_temp.assert_true(
  (select result_code = 'CANCELLED'
   from api.redeem_reward('CHIC-RD4A3', 'RD4A-CAN', 300000, true)),
  'RD13 Cancelled Reward must not redeem'
);
select pg_temp.assert_true(
  (select result_code = 'MINIMUM_SPEND_NOT_MET'
   from api.redeem_reward('CHIC-RD4A4', 'RD4A-MIN', 299999, true)),
  'RD14 Bill below minimum must not redeem'
);
select pg_temp.assert_true(
  (select result_code = 'REDEEMED'
   from api.redeem_reward('CHIC-RD4A4', 'RD4A-EQUAL', 300000, true)),
  'RD15 Bill equal to minimum must redeem'
);
select pg_temp.assert_true(
  (select result_code = 'REDEEMED'
   from api.redeem_reward('CHIC-RD4A5', 'RD4A-ABOVE', 300001, true)),
  'RD16 Bill above minimum must redeem'
);
reset role;

-- RD17-RD18: no browser-controlled actor or timestamp overload exists.
select pg_temp.assert_true(
  to_regprocedure('api.redeem_reward(text,text,bigint,boolean,uuid)') is null,
  'RD17 Browser must not be able to supply redeemed_by'
);
select pg_temp.assert_true(
  to_regprocedure('api.redeem_reward(text,text,bigint,boolean,timestamptz)') is null,
  'RD18 Browser must not be able to supply redeemed_at'
);

-- RD19: inactive Staff cannot redeem.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000003', true);
select pg_temp.assert_raises(
  $$select * from api.redeem_reward('CHIC-RD4A7', 'RD4A-INACTIVE', 300000, true)$$,
  '42501',
  'RD19 Inactive Staff must not redeem'
);
reset role;

-- RD20: cross-branch redemption is denied without operational detail.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true(
  (select result_code = 'WRONG_BRANCH' and reward_code is null and reward_name is null
   from api.redeem_reward('CHIC-RD4A6', 'RD4A-WRONG', 300000, true)),
  'RD20 Wrong-branch Staff must be denied without Reward detail'
);
reset role;

-- RD21: anon cannot execute either Staff operation.
set local role anon;
select pg_temp.assert_raises(
  $$select * from api.get_reward_for_redemption('CHIC-RD4A7')$$,
  '42501',
  'RD21 Anonymous caller must not execute lookup'
);
select pg_temp.assert_raises(
  $$select * from api.redeem_reward('CHIC-RD4A7', 'RD4A-ANON', 300000, true)$$,
  '42501',
  'RD21 Anonymous caller must not execute redemption'
);
reset role;

-- RD22: authenticated browser role still cannot mutate Reward table directly.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_raises(
  $$update private.rewards set redeemed_at = now()
    where id = 'd6000000-0000-0000-0000-000000000007'$$,
  '42501',
  'RD22 Browser role must not update Reward table directly'
);

-- RD23: Staff API omits internal IDs, economics, probability, inventory, and Audit.
select pg_temp.assert_true(
  (select not (to_jsonb(lookup_result) ?| array[
      'reward_id', 'gift_id', 'gift_entry_id', 'prize_id', 'campaign_id',
      'estimated_chic_cost_vnd', 'weight', 'max_quantity', 'issued_quantity',
      'is_fallback', 'audit', 'actor_id', 'redeemed_by'
    ])
   from api.get_reward_for_redemption('CHIC-RD4A7') as lookup_result),
  'RD23 Staff lookup must expose only required operational fields'
);
reset role;

-- RD24: rejected redemption creates no successful Audit or partial mutation.
select pg_temp.assert_true(
  (select redeemed_at is null and redeemed_by is null
      and redemption_bill_code is null and redemption_bill_amount_vnd is null
   from private.rewards where id = 'd6000000-0000-0000-0000-000000000002')
  and not exists (
    select 1 from private.audit_logs
    where action = 'REDEEM_GIFT' and entity_id = 'd6000000-0000-0000-0000-000000000002'
  ),
  'RD24 Failed redemption must leave no partial state or successful Audit'
);

-- RD25: redemption leaves the immutable Customer entitlement snapshot unchanged.
select pg_temp.assert_true(
  (select prize_snapshot = '{"name":"Phase 4A Nail Care","type":"FREE_SERVICE","customer_description":"Tặng chăm sóc móng cơ bản.","customer_value_vnd":100000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":"Dịch vụ nail","campaign_terms":"Điều kiện Phase 4A.","expiry_days":30}'::jsonb
   from private.rewards where id = 'd6000000-0000-0000-0000-000000000001'),
  'RD25 Customer entitlement snapshot must remain unchanged'
);

-- RDC03: a failure after the Reward update rolls the whole statement back.
create or replace function pg_temp.fail_phase_4a_redeem_audit()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Injected Phase 4A Audit failure' using errcode = 'P0001';
end;
$$;

create trigger phase_4a_fail_redeem_audit
before insert on private.audit_logs
for each row
when (
  new.action = 'REDEEM_GIFT'
  and new.entity_id = 'd6000000-0000-0000-0000-000000000007'::uuid
)
execute function pg_temp.fail_phase_4a_redeem_audit();

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_raises(
  $$select * from api.redeem_reward('CHIC-RD4A7', 'RD4A-FAILURE', 300000, true)$$,
  'P0001',
  'RDC03 Injected transaction failure must propagate safely'
);
reset role;

select pg_temp.assert_true(
  (select redeemed_at is null and redeemed_by is null
      and redemption_bill_code is null and redemption_bill_amount_vnd is null
   from private.rewards where id = 'd6000000-0000-0000-0000-000000000007')
  and not exists (
    select 1 from private.audit_logs
    where action = 'REDEEM_GIFT' and entity_id = 'd6000000-0000-0000-0000-000000000007'
  ),
  'RDC03 Failure must leave Reward unredeemed and no successful Audit'
);

rollback;
