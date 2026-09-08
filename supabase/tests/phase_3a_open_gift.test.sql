-- Phase 3A atomic Reward engine checks.
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

insert into private.branches (id, code, name)
values (
  'b1000000-0000-0000-0000-000000000001',
  'PHASE-3A-TEST',
  'Phase 3A Test Branch'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  'b1100000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'phase3a-admin@example.invalid', '', now(),
  '{}', '{}', now(), now()
);

insert into private.staff_profiles (id, branch_id, name, role, active)
values (
  'b1100000-0000-0000-0000-000000000001',
  'b1000000-0000-0000-0000-000000000001',
  'Phase 3A Admin',
  'ADMIN',
  true
);

insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
values
  (
    'b2000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001',
    'Phase 3A Weighted Campaign',
    'DRAFT',
    statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '30 days',
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b2000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000001',
    'Phase 3A Limited Campaign',
    'DRAFT',
    statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '30 days',
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b2000000-0000-0000-0000-000000000003',
    'b1000000-0000-0000-0000-000000000001',
    'Phase 3A Unlimited Campaign',
    'DRAFT',
    statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '30 days',
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b2000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000001',
    'Phase 3A Failure Campaign',
    'DRAFT',
    statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '30 days',
    'b1100000-0000-0000-0000-000000000001'
  );

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  gift_open_deadline_hours, headline, description, terms, created_by
)
values
  (
    'b3000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    1, 200000, 24, 'Weighted test', 'Phase 3A only.',
    'Điều kiện weighted test.',
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b3000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000002',
    1, 200000, 24, 'Limited test', 'Phase 3A only.',
    'Điều kiện limited test.',
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b3000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000003',
    1, 200000, 24, 'Unlimited test', 'Phase 3A only.',
    'Điều kiện unlimited test.',
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b3000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000004',
    1, 200000, 24, 'Failure test', 'Phase 3A only.',
    'Điều kiện failure test.',
    'b1100000-0000-0000-0000-000000000001'
  );

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, discount_percent,
  minimum_spend_vnd, applicable_service, expiry_days,
  weight, max_quantity, issued_quantity, is_fallback, active
)
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'Normal 1', 'FREE_SERVICE', 'Normal weight 1',
    10000, 1000, null, 0, 'Nail', 7,
    1, null, 0, false, true
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000001',
    'Normal 3', 'PERCENT_DISCOUNT', 'Normal weight 3',
    30000, 3000, 10, 200000, 'Spa', 14,
    3, null, 0, false, true
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000001',
    'Normal 6', 'CASH_VOUCHER', 'Normal weight 6',
    60000, 6000, null, 100000, null, 30,
    6, null, 0, false, true
  ),
  (
    'b4000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000001',
    'Inactive normal', 'FREE_SERVICE', 'Must never be selected',
    999999, 999999, null, 0, null, 30,
    100, null, 0, false, false
  ),
  (
    'b4000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    'Weighted fallback', 'CUSTOM_REWARD', 'Exhaustion only',
    5000, 500, null, 0, null, 7,
    1, null, 0, true, true
  ),
  (
    'b4000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000002',
    'Last limited normal', 'FREE_SERVICE', 'Only one available',
    20000, 2000, null, 0, null, 7,
    5, 1, 0, false, true
  ),
  (
    'b4000000-0000-0000-0000-000000000012',
    'b3000000-0000-0000-0000-000000000002',
    'Limited fallback', 'CUSTOM_REWARD', 'Fallback after exhaustion',
    5000, 500, null, 0, null, 7,
    1, null, 0, true, true
  ),
  (
    'b4000000-0000-0000-0000-000000000021',
    'b3000000-0000-0000-0000-000000000003',
    'Unlimited normal', 'SERVICE_UPGRADE', 'Always remains eligible',
    20000, 2000, null, 0, null, 10,
    7, null, 100, false, true
  ),
  (
    'b4000000-0000-0000-0000-000000000022',
    'b3000000-0000-0000-0000-000000000003',
    'Unlimited fallback', 'CUSTOM_REWARD', 'Fallback only',
    5000, 500, null, 0, null, 7,
    1, null, 0, true, true
  );

update private.campaign_versions
set published_at = statement_timestamp()
where id in (
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000002',
  'b3000000-0000-0000-0000-000000000003'
);

update private.campaigns
set current_version_id = case id
      when 'b2000000-0000-0000-0000-000000000001'::uuid
        then 'b3000000-0000-0000-0000-000000000001'::uuid
      when 'b2000000-0000-0000-0000-000000000002'::uuid
        then 'b3000000-0000-0000-0000-000000000002'::uuid
      when 'b2000000-0000-0000-0000-000000000003'::uuid
        then 'b3000000-0000-0000-0000-000000000003'::uuid
    end,
    status = case id
      when 'b2000000-0000-0000-0000-000000000001'::uuid
        then 'ACTIVE'::private.campaign_status
      else 'ENDED'::private.campaign_status
    end
where id in (
  'b2000000-0000-0000-0000-000000000001',
  'b2000000-0000-0000-0000-000000000002',
  'b2000000-0000-0000-0000-000000000003'
);

insert into private.gift_entries (
  id, branch_id, bill_code_entered, bill_amount_vnd,
  campaign_version_id, gift_token, status, open_expires_at,
  created_by, cancelled_at, cancelled_by
)
values
  (
    'b5000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-VALID', 300000,
    'b3000000-0000-0000-0000-000000000001',
    '1111111111111111111111111111111111111111111111111111111111111111',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-CANCELLED', 300000,
    'b3000000-0000-0000-0000-000000000001',
    '2222222222222222222222222222222222222222222222222222222222222222',
    'CANCELLED', null,
    'b1100000-0000-0000-0000-000000000001', statement_timestamp(),
    'b1100000-0000-0000-0000-000000000001'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-EXPIRED', 300000,
    'b3000000-0000-0000-0000-000000000001',
    '3333333333333333333333333333333333333333333333333333333333333333',
    'ELIGIBLE', statement_timestamp() - interval '1 second',
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-ENDED', 300000,
    'b3000000-0000-0000-0000-000000000001',
    '4444444444444444444444444444444444444444444444444444444444444444',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-ARCHIVED', 300000,
    'b3000000-0000-0000-0000-000000000001',
    '5555555555555555555555555555555555555555555555555555555555555555',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000011',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-LIMIT-1', 300000,
    'b3000000-0000-0000-0000-000000000002',
    '6666666666666666666666666666666666666666666666666666666666666666',
    'ELIGIBLE', null,
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000012',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-LIMIT-2', 300000,
    'b3000000-0000-0000-0000-000000000002',
    '7777777777777777777777777777777777777777777777777777777777777777',
    'ELIGIBLE', null,
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000021',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-UNLIMITED', 300000,
    'b3000000-0000-0000-0000-000000000003',
    '8888888888888888888888888888888888888888888888888888888888888888',
    'ELIGIBLE', null,
    'b1100000-0000-0000-0000-000000000001', null, null
  ),
  (
    'b5000000-0000-0000-0000-000000000031',
    'b1000000-0000-0000-0000-000000000001',
    'P3A-FAILURE', 300000,
    'b3000000-0000-0000-0000-000000000004',
    '9999999999999999999999999999999999999999999999999999999999999999',
    'ELIGIBLE', null,
    'b1100000-0000-0000-0000-000000000001', null, null
  );

-- OG01: invalid input cannot create a Reward.
set local role anon;
select pg_temp.assert_true(
  (select result_code = 'INVALID_GIFT' and not reward_available
   from api.open_gift('invalid-token')),
  'OG01 Invalid Gift Token must return safely'
);
reset role;
select pg_temp.assert_true(
  (
    select count(*) = 0
    from private.rewards as r
    join private.gift_entries as ge on ge.id = r.gift_entry_id
    where ge.branch_id = 'b1000000-0000-0000-0000-000000000001'
  ),
  'OG01 Invalid Gift Token must create no Reward'
);

-- OG12, OG17, OG18: deterministic relative-weight boundaries exclude inactive Prizes.
select pg_temp.assert_true(
  private.select_weighted_prize(
    'b3000000-0000-0000-0000-000000000001', 0
  ) = 'b4000000-0000-0000-0000-000000000001',
  'OG18 Random value 0 must select first weight bucket'
);
select pg_temp.assert_true(
  private.select_weighted_prize(
    'b3000000-0000-0000-0000-000000000001', 0.099999
  ) = 'b4000000-0000-0000-0000-000000000001',
  'OG18 Value below 0.1 must stay in the first bucket'
);
select pg_temp.assert_true(
  private.select_weighted_prize(
    'b3000000-0000-0000-0000-000000000001', 0.1
  ) = 'b4000000-0000-0000-0000-000000000002',
  'OG18 Exact 0.1 boundary must enter the second bucket'
);
select pg_temp.assert_true(
  private.select_weighted_prize(
    'b3000000-0000-0000-0000-000000000001', 0.4
  ) = 'b4000000-0000-0000-0000-000000000003',
  'OG18 Exact 0.4 boundary must enter the third bucket'
);
select pg_temp.assert_true(
  private.select_weighted_prize(
    'b3000000-0000-0000-0000-000000000001', 0.999999
  ) = 'b4000000-0000-0000-0000-000000000003',
  'OG12/OG18 Inactive Prize must not enter weighted boundaries'
);
select pg_temp.assert_true(
  (
    select sum(weight) = 10
    from private.prizes
    where campaign_version_id = 'b3000000-0000-0000-0000-000000000001'
      and active
      and not is_fallback
  ),
  'OG17 Relative weights must work without totalling 100'
);

-- OG02, OG03, OG13: first opening creates one non-fallback Reward.
set local role anon;
select pg_temp.assert_true(
  (
    select result_code = 'OPENED_NOW'
      and reward_available
      and reward_status = 'AVAILABLE'
      and reward_code ~ '^CHIC-[A-Z0-9]{5,16}$'
    from api.open_gift(
      '1111111111111111111111111111111111111111111111111111111111111111'
    )
  ),
  'OG02-OG03 First valid open must return one new Reward'
);
reset role;

select pg_temp.assert_true(
  (
    select count(*) = 1
      and bool_and(not p.is_fallback)
      and bool_and(p.active)
    from private.rewards as r
    join private.prizes as p on p.id = r.prize_id
    where r.gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  'OG02/OG13 First open must create one normal Prize Reward while normal inventory exists'
);

select set_config(
  'chic_gift.phase_3a_reward_code',
  (
    select r.reward_code
    from private.rewards as r
    where r.gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  true
);
select set_config(
  'chic_gift.phase_3a_reward_name',
  (
    select r.prize_snapshot ->> 'name'
    from private.rewards as r
    where r.gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  true
);

-- OG04-OG07: repeat opening is stable and idempotent.
set local role anon;
select pg_temp.assert_true(
  (
    select result_code = 'ALREADY_OPENED'
      and reward_code = current_setting('chic_gift.phase_3a_reward_code')
      and reward_name = current_setting('chic_gift.phase_3a_reward_name')
    from api.open_gift(
      '1111111111111111111111111111111111111111111111111111111111111111'
    )
  ),
  'OG04-OG06 Repeat open must return the same Prize and Reward Code'
);
reset role;

select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.rewards
    where gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  'OG07 Repeat open must not create a second Reward'
);

-- OG08-OG09: cancelled and expired Gifts cannot open.
set local role anon;
select pg_temp.assert_true(
  (select result_code = 'GIFT_CANCELLED' and not reward_available
   from api.open_gift(
     '2222222222222222222222222222222222222222222222222222222222222222'
   )),
  'OG08 Cancelled Gift must not open'
);
select pg_temp.assert_true(
  (select result_code = 'OPEN_WINDOW_EXPIRED' and not reward_available
   from api.open_gift(
     '3333333333333333333333333333333333333333333333333333333333333333'
   )),
  'OG09 Expired opening window must not open'
);
reset role;
select pg_temp.assert_true(
  (
    select count(*) = 0
    from private.rewards
    where gift_entry_id in (
      'b5000000-0000-0000-0000-000000000002',
      'b5000000-0000-0000-0000-000000000003'
    )
  ),
  'OG08-OG09 Cancelled/expired Gifts must create no Reward'
);

-- OG10-OG11: Campaign lifecycle after issuance does not revoke Gift entitlement.
update private.campaigns
set status = 'ENDED'
where id = 'b2000000-0000-0000-0000-000000000001';
set local role anon;
select pg_temp.assert_true(
  (select result_code = 'OPENED_NOW' and reward_available
   from api.open_gift(
     '4444444444444444444444444444444444444444444444444444444444444444'
   )),
  'OG10 ENDED Campaign must not revoke an issued Gift'
);
reset role;

update private.campaigns
set status = 'ARCHIVED'
where id = 'b2000000-0000-0000-0000-000000000001';
set local role anon;
select pg_temp.assert_true(
  (select result_code = 'OPENED_NOW' and reward_available
   from api.open_gift(
     '5555555555555555555555555555555555555555555555555555555555555555'
   )),
  'OG11 ARCHIVED Campaign must not revoke an issued Gift'
);
reset role;

-- OG14-OG15: one finite normal unit, then fallback with no oversell.
set local role anon;
select pg_temp.assert_true(
  (select result_code = 'OPENED_NOW' and reward_name = 'Last limited normal'
   from api.open_gift(
     '6666666666666666666666666666666666666666666666666666666666666666'
   )),
  'OG15 Available finite normal Prize must be selected'
);
select pg_temp.assert_true(
  (select result_code = 'OPENED_NOW' and reward_name = 'Limited fallback'
   from api.open_gift(
     '7777777777777777777777777777777777777777777777777777777777777777'
   )),
  'OG14 Fallback must be selected only after normal exhaustion'
);
reset role;
select pg_temp.assert_true(
  (
    select issued_quantity = 1 and issued_quantity <= max_quantity
    from private.prizes
    where id = 'b4000000-0000-0000-0000-000000000011'
  ),
  'OG15 Finite max_quantity must never be exceeded'
);

-- OG16: unlimited normal remains eligible at a high issued count.
set local role anon;
select pg_temp.assert_true(
  (select result_code = 'OPENED_NOW' and reward_name = 'Unlimited normal'
   from api.open_gift(
     '8888888888888888888888888888888888888888888888888888888888888888'
   )),
  'OG16 Unlimited normal Prize must remain eligible'
);
reset role;
select pg_temp.assert_true(
  (
    select issued_quantity = 101 and max_quantity is null
    from private.prizes
    where id = 'b4000000-0000-0000-0000-000000000021'
  ),
  'OG16 Unlimited Prize issued count may increase without a cap'
);

-- OG19-OG20: public contract has one Customer-controlled parameter only.
select pg_temp.assert_true(
  (
    select count(*) = 1
      and bool_and(p.pronargs = 1)
      and bool_and(
        pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_gift_token text'
      )
    from pg_catalog.pg_proc as p
    join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and p.proname = 'open_gift'
  ),
  'OG19 Browser must be able to submit only Gift Token'
);
select pg_temp.assert_true(
  to_regprocedure('api.open_gift(text,uuid)') is null
    and to_regprocedure('api.open_gift(text,numeric)') is null,
  'OG19-OG20 No public Prize or random-value overload may exist'
);

-- OG21-OG23: expiry, immutable snapshot, and Reward Code are server-generated.
select pg_temp.assert_true(
  (
    select r.expires_at > r.created_at
      and r.expires_at >= r.created_at
        + pg_catalog.make_interval(
          days => (r.prize_snapshot ->> 'expiry_days')::integer
        )
      and r.reward_code ~ '^CHIC-[A-Z0-9]{5,16}$'
    from private.rewards as r
    where r.gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  'OG21/OG23 Reward expiry and unique-format code must be generated server-side'
);
select pg_temp.assert_true(
  (
    select r.prize_snapshot ?& array[
      'name',
      'type',
      'customer_description',
      'customer_value_vnd',
      'discount_percent',
      'minimum_spend_vnd',
      'applicable_service',
      'campaign_terms',
      'expiry_days'
    ]
    from private.rewards as r
    where r.gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
  ),
  'OG22 Reward snapshot must preserve all Customer entitlement fields'
);
select pg_temp.assert_true(
  (
    select count(*) = count(distinct reward_code)
    from private.rewards
  ),
  'OG23 Reward Codes must remain unique'
);

-- OG24-OG25: one first-open Audit event, no replay spam.
select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.audit_logs
    where action = 'OPEN_GIFT'
      and entity_type = 'REWARD'
      and entity_id = (
        select id
        from private.rewards
        where gift_entry_id = 'b5000000-0000-0000-0000-000000000001'
      )
  ),
  'OG24-OG25 First open must write one Audit and repeat must not duplicate it'
);

-- OG26-OG28: public payload omits every protected category.
set local role anon;
select pg_temp.assert_true(
  (
    select not (
      to_jsonb(open_result) ?| array[
        'bill_code', 'bill_amount', 'bill_amount_vnd',
        'staff', 'staff_id', 'created_by',
        'gift_id', 'reward_id', 'prize_id', 'campaign_id',
        'campaign_version_id', 'weight', 'prize_weight',
        'estimated_chic_cost_vnd', 'max_quantity', 'issued_quantity',
        'remaining_inventory', 'probability', 'is_fallback',
        'audit', 'audit_data', 'cancellation_reason'
      ]
    )
    from api.open_gift(
      '1111111111111111111111111111111111111111111111111111111111111111'
    ) as open_result
  ),
  'OG26-OG28 Public response must omit Bill, Staff, IDs, economics, inventory, probability, and Audit data'
);

-- OG29-OG30: deny direct tables/helper; expose only hardened RPC.
select pg_temp.assert_raises(
  $$select * from private.gift_entries$$,
  '42501',
  'OG29 Anonymous caller must not read Gift rows'
);
select pg_temp.assert_raises(
  $$insert into private.rewards (
      gift_entry_id, prize_id, reward_code, prize_snapshot, expires_at
    ) values (
      'b5000000-0000-0000-0000-000000000001',
      'b4000000-0000-0000-0000-000000000001',
      'CHIC-ANON01', '{}', statement_timestamp() + interval '1 day'
    )$$,
  '42501',
  'OG29 Anonymous caller must not write Reward rows'
);
select pg_temp.assert_raises(
  $$select private.select_weighted_prize(
      'b3000000-0000-0000-0000-000000000001', 0.5
    )$$,
  '42501',
  'OG20/OG30 Anonymous caller must not control the deterministic selector'
);
reset role;

select pg_temp.assert_true(
  has_function_privilege('anon', 'api.open_gift(text)', 'execute')
    and has_function_privilege('authenticated', 'api.open_gift(text)', 'execute')
    and not has_function_privilege(
      'anon',
      'private.select_weighted_prize(uuid,numeric)',
      'execute'
    )
    and (
      select p.prosecdef
        and array_to_string(p.proconfig, ',') like 'search_path=%'
      from pg_catalog.pg_proc as p
      where p.oid = 'api.open_gift(text)'::regprocedure
    ),
  'OG30 Public function must use narrow grants, SECURITY DEFINER, and fixed search_path'
);

-- CON05 support: a configuration failure leaves no partial Reward or Audit.
select pg_temp.assert_raises(
  $$select * from api.open_gift(
      '9999999999999999999999999999999999999999999999999999999999999999'
    )$$,
  'P0001',
  'CON05 Invalid unpublished configuration must fail atomically'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from private.rewards
    where gift_entry_id = 'b5000000-0000-0000-0000-000000000031'
  )
  and not exists (
    select 1
    from private.audit_logs
    where bill_code_normalized = 'P3A-FAILURE'
  ),
  'CON05 Failed transaction must leave no partial Reward or Audit'
);

rollback;
