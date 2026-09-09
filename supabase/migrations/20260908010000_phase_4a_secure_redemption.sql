-- CHIC GIFT Phase 4A: Staff-only Reward lookup and atomic redemption.
-- Admin workflows, overrides, and KiotViet integration remain excluded.

alter table private.rewards
  add column redemption_bill_code text,
  add column redemption_bill_amount_vnd bigint;

alter table private.rewards
  drop constraint rewards_redemption_pair;

alter table private.rewards
  add constraint rewards_redemption_fields_consistent check (
    (
      redeemed_at is null
      and redeemed_by is null
      and redemption_bill_code is null
      and redemption_bill_amount_vnd is null
    )
    or
    (
      redeemed_at is not null
      and redeemed_by is not null
      and redemption_bill_code is not null
      and redemption_bill_amount_vnd is not null
    )
  ),
  add constraint rewards_redemption_bill_code_normalized check (
    redemption_bill_code is null
    or redemption_bill_code = private.normalize_bill_code(redemption_bill_code)
  ),
  add constraint rewards_redemption_bill_amount_positive check (
    redemption_bill_amount_vnd is null
    or redemption_bill_amount_vnd > 0
  );

comment on column private.rewards.redemption_bill_code is
  'Normalized KiotViet Bill Code manually verified by Staff at redemption.';
comment on column private.rewards.redemption_bill_amount_vnd is
  'Integer VND amount manually verified by Staff at redemption.';

create or replace function api.get_reward_for_redemption(p_reward_code text)
returns table (
  result_code text,
  reward_status text,
  reward_name text,
  reward_description text,
  reward_type text,
  customer_value_vnd bigint,
  discount_percent numeric,
  minimum_spend_vnd bigint,
  applicable_service text,
  reward_terms text,
  reward_code text,
  reward_expires_at timestamptz,
  redeemable boolean,
  redeemed_at timestamptz,
  redemption_bill_code text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff private.staff_profiles%rowtype;
  v_reward private.rewards%rowtype;
  v_gift_status private.gift_status;
  v_reward_branch_id uuid;
  v_normalized_reward_code text;
  v_result_code text;
  v_reward_status text;
  v_redeemable boolean;
begin
  select sp.*
  into v_staff
  from private.staff_profiles as sp
  join private.branches as b on b.id = sp.branch_id
  where sp.id = (select auth.uid())
    and sp.active
    and b.active
    and sp.role in ('STAFF', 'ADMIN');

  if not found then
    raise exception 'Active Staff access required'
      using errcode = '42501';
  end if;

  v_normalized_reward_code := upper(
    regexp_replace(
      coalesce(p_reward_code, ''),
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
  );

  if v_normalized_reward_code = ''
    or v_normalized_reward_code ~ '[[:space:]]'
    or v_normalized_reward_code !~ '^CHIC-[A-Z0-9]{5,16}$'
  then
    return query select
      'REWARD_NOT_FOUND'::text,
      null::text, null::text, null::text, null::text,
      null::bigint, null::numeric, null::bigint, null::text, null::text,
      null::text, null::timestamptz, false, null::timestamptz, null::text;
    return;
  end if;

  select r.*
  into v_reward
  from private.rewards as r
  where r.reward_code = v_normalized_reward_code;

  if not found then
    return query select
      'REWARD_NOT_FOUND'::text,
      null::text, null::text, null::text, null::text,
      null::bigint, null::numeric, null::bigint, null::text, null::text,
      null::text, null::timestamptz, false, null::timestamptz, null::text;
    return;
  end if;

  select ge.status, ge.branch_id
  into v_gift_status, v_reward_branch_id
  from private.gift_entries as ge
  where ge.id = v_reward.gift_entry_id;

  if v_reward_branch_id <> v_staff.branch_id then
    return query select
      'WRONG_BRANCH'::text,
      null::text, null::text, null::text, null::text,
      null::bigint, null::numeric, null::bigint, null::text, null::text,
      null::text, null::timestamptz, false, null::timestamptz, null::text;
    return;
  end if;

  if v_gift_status = 'CANCELLED' then
    v_result_code := 'CANCELLED';
    v_reward_status := 'CANCELLED';
    v_redeemable := false;
  elsif v_reward.redeemed_at is not null then
    v_result_code := 'ALREADY_REDEEMED';
    v_reward_status := 'REDEEMED';
    v_redeemable := false;
  elsif pg_catalog.statement_timestamp() > v_reward.expires_at then
    v_result_code := 'REWARD_EXPIRED';
    v_reward_status := 'EXPIRED';
    v_redeemable := false;
  else
    v_result_code := 'REWARD_AVAILABLE';
    v_reward_status := 'AVAILABLE';
    v_redeemable := true;
  end if;

  return query select
    v_result_code,
    v_reward_status,
    v_reward.prize_snapshot ->> 'name',
    v_reward.prize_snapshot ->> 'customer_description',
    v_reward.prize_snapshot ->> 'type',
    (v_reward.prize_snapshot ->> 'customer_value_vnd')::bigint,
    (v_reward.prize_snapshot ->> 'discount_percent')::numeric,
    (v_reward.prize_snapshot ->> 'minimum_spend_vnd')::bigint,
    v_reward.prize_snapshot ->> 'applicable_service',
    v_reward.prize_snapshot ->> 'campaign_terms',
    v_reward.reward_code,
    v_reward.expires_at,
    v_redeemable,
    v_reward.redeemed_at,
    v_reward.redemption_bill_code;
end;
$$;

comment on function api.get_reward_for_redemption(text) is
  'Returns only same-branch operational Reward data to authenticated active Staff.';

create or replace function api.redeem_reward(
  p_reward_code text,
  p_redemption_bill_code text,
  p_redemption_bill_amount_vnd bigint,
  p_conditions_confirmed boolean
)
returns table (
  result_code text,
  reward_status text,
  reward_name text,
  reward_description text,
  reward_type text,
  customer_value_vnd bigint,
  discount_percent numeric,
  minimum_spend_vnd bigint,
  applicable_service text,
  reward_terms text,
  reward_code text,
  reward_expires_at timestamptz,
  redeemable boolean,
  redeemed_at timestamptz,
  redemption_bill_code text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff private.staff_profiles%rowtype;
  v_reward private.rewards%rowtype;
  v_gift_status private.gift_status;
  v_reward_branch_id uuid;
  v_normalized_reward_code text;
  v_normalized_bill_code text;
  v_minimum_spend_vnd bigint;
  v_result_code text;
  v_reward_status text;
begin
  select sp.*
  into v_staff
  from private.staff_profiles as sp
  join private.branches as b on b.id = sp.branch_id
  where sp.id = (select auth.uid())
    and sp.active
    and b.active
    and sp.role in ('STAFF', 'ADMIN');

  if not found then
    raise exception 'Active Staff access required'
      using errcode = '42501';
  end if;

  v_normalized_reward_code := upper(
    regexp_replace(
      coalesce(p_reward_code, ''),
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
  );

  if v_normalized_reward_code = ''
    or v_normalized_reward_code ~ '[[:space:]]'
    or v_normalized_reward_code !~ '^CHIC-[A-Z0-9]{5,16}$'
  then
    return query select
      'REWARD_NOT_FOUND'::text,
      null::text, null::text, null::text, null::text,
      null::bigint, null::numeric, null::bigint, null::text, null::text,
      null::text, null::timestamptz, false, null::timestamptz, null::text;
    return;
  end if;

  select r.*
  into v_reward
  from private.rewards as r
  where r.reward_code = v_normalized_reward_code
  for update;

  if not found then
    return query select
      'REWARD_NOT_FOUND'::text,
      null::text, null::text, null::text, null::text,
      null::bigint, null::numeric, null::bigint, null::text, null::text,
      null::text, null::timestamptz, false, null::timestamptz, null::text;
    return;
  end if;

  select ge.status, ge.branch_id
  into v_gift_status, v_reward_branch_id
  from private.gift_entries as ge
  where ge.id = v_reward.gift_entry_id;

  if v_reward_branch_id <> v_staff.branch_id then
    return query select
      'WRONG_BRANCH'::text,
      null::text, null::text, null::text, null::text,
      null::bigint, null::numeric, null::bigint, null::text, null::text,
      null::text, null::timestamptz, false, null::timestamptz, null::text;
    return;
  end if;

  if v_gift_status = 'CANCELLED' then
    v_result_code := 'CANCELLED';
    v_reward_status := 'CANCELLED';
  elsif v_reward.redeemed_at is not null then
    v_result_code := 'ALREADY_REDEEMED';
    v_reward_status := 'REDEEMED';
  elsif pg_catalog.statement_timestamp() > v_reward.expires_at then
    v_result_code := 'REWARD_EXPIRED';
    v_reward_status := 'EXPIRED';
  elsif not coalesce(p_conditions_confirmed, false) then
    v_result_code := 'CONDITIONS_NOT_CONFIRMED';
    v_reward_status := 'AVAILABLE';
  elsif p_redemption_bill_amount_vnd is null
    or p_redemption_bill_amount_vnd <= 0
  then
    v_result_code := 'INVALID_REDEMPTION_BILL_AMOUNT';
    v_reward_status := 'AVAILABLE';
  else
    v_normalized_bill_code := upper(
      regexp_replace(
        coalesce(p_redemption_bill_code, ''),
        '^[[:space:]]+|[[:space:]]+$',
        '',
        'g'
      )
    );

    if v_normalized_bill_code = ''
      or v_normalized_bill_code ~ '[[:space:]]'
      or char_length(v_normalized_bill_code) > 100
    then
      v_result_code := 'INVALID_REDEMPTION_BILL_CODE';
      v_reward_status := 'AVAILABLE';
    else
      v_minimum_spend_vnd := coalesce(
        (v_reward.prize_snapshot ->> 'minimum_spend_vnd')::bigint,
        0
      );
    end if;

    if v_result_code is null
      and p_redemption_bill_amount_vnd < v_minimum_spend_vnd
    then
      v_result_code := 'MINIMUM_SPEND_NOT_MET';
      v_reward_status := 'AVAILABLE';
    elsif v_result_code is null then
      update private.rewards as target_reward
      set redeemed_at = pg_catalog.statement_timestamp(),
          redeemed_by = v_staff.id,
          redemption_bill_code = v_normalized_bill_code,
          redemption_bill_amount_vnd = p_redemption_bill_amount_vnd
      where target_reward.id = v_reward.id
        and target_reward.redeemed_at is null
      returning target_reward.* into v_reward;

      if not found then
        raise exception 'Reward redemption changed concurrently; retry safely'
          using errcode = '40001';
      end if;

      insert into private.audit_logs (
        action,
        actor_id,
        actor_role,
        branch_id,
        entity_type,
        entity_id,
        bill_code_normalized,
        old_data,
        new_data,
        metadata
      )
      values (
        'REDEEM_GIFT',
        v_staff.id,
        v_staff.role,
        v_staff.branch_id,
        'REWARD',
        v_reward.id,
        v_normalized_bill_code,
        pg_catalog.jsonb_build_object('reward_status', 'AVAILABLE'),
        pg_catalog.jsonb_build_object(
          'reward_status', 'REDEEMED',
          'gift_entry_id', v_reward.gift_entry_id,
          'reward_code', v_reward.reward_code,
          'redeemed_at', v_reward.redeemed_at,
          'redeemed_by', v_reward.redeemed_by,
          'redemption_bill_code', v_reward.redemption_bill_code,
          'redemption_bill_amount_vnd', v_reward.redemption_bill_amount_vnd
        ),
        pg_catalog.jsonb_build_object('source', 'STAFF_REDEMPTION')
      );

      v_result_code := 'REDEEMED';
      v_reward_status := 'REDEEMED';
    end if;
  end if;

  return query select
    v_result_code,
    v_reward_status,
    v_reward.prize_snapshot ->> 'name',
    v_reward.prize_snapshot ->> 'customer_description',
    v_reward.prize_snapshot ->> 'type',
    (v_reward.prize_snapshot ->> 'customer_value_vnd')::bigint,
    (v_reward.prize_snapshot ->> 'discount_percent')::numeric,
    (v_reward.prize_snapshot ->> 'minimum_spend_vnd')::bigint,
    v_reward.prize_snapshot ->> 'applicable_service',
    v_reward.prize_snapshot ->> 'campaign_terms',
    v_reward.reward_code,
    v_reward.expires_at,
    v_result_code = 'REWARD_AVAILABLE',
    v_reward.redeemed_at,
    v_reward.redemption_bill_code;
end;
$$;

comment on function api.redeem_reward(text, text, bigint, boolean) is
  'Atomically validates and redeems one same-branch Reward for authenticated active Staff.';

revoke all on function api.get_reward_for_redemption(text)
  from public, anon, authenticated, service_role;
revoke all on function api.redeem_reward(text, text, bigint, boolean)
  from public, anon, authenticated, service_role;

grant usage on schema api to authenticated;
grant execute on function api.get_reward_for_redemption(text) to authenticated;
grant execute on function api.redeem_reward(text, text, bigint, boolean) to authenticated;
