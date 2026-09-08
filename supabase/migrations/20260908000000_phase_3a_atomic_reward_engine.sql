-- CHIC GIFT Phase 3A: atomic, idempotent public Gift opening.
-- Customer UI, redemption, and administration remain intentionally excluded.

create or replace function private.select_weighted_prize(
  p_campaign_version_id uuid,
  p_random_value numeric
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_prize_id uuid;
begin
  if p_random_value is null
    or p_random_value < 0
    or p_random_value >= 1
  then
    raise exception 'Random value must be in the range [0, 1)'
      using errcode = '22023';
  end if;

  with eligible_normal as (
    select
      p.id,
      p.weight::numeric as weight
    from private.prizes as p
    where p.campaign_version_id = p_campaign_version_id
      and p.active
      and not p.is_fallback
      and p.weight > 0
      and (
        p.max_quantity is null
        or p.issued_quantity < p.max_quantity
      )
  ), weighted_normal as (
    select
      en.id,
      sum(en.weight) over (
        order by en.id
        rows between unbounded preceding and current row
      ) as cumulative_weight,
      sum(en.weight) over () as total_weight
    from eligible_normal as en
  )
  select wn.id
  into v_prize_id
  from weighted_normal as wn
  where p_random_value * wn.total_weight < wn.cumulative_weight
  order by wn.id
  limit 1;

  if found then
    return v_prize_id;
  end if;

  select p.id
  into v_prize_id
  from private.prizes as p
  where p.campaign_version_id = p_campaign_version_id
    and p.active
    and p.is_fallback
    and p.max_quantity is null;

  if not found then
    raise exception 'Reward assignment is temporarily unavailable'
      using errcode = 'P0001';
  end if;

  return v_prize_id;
end;
$$;

comment on function private.select_weighted_prize(uuid, numeric) is
  'Internal deterministic weighted selector. Normal Prizes are weighted; fallback is used only after normal exhaustion.';

revoke all on function private.select_weighted_prize(uuid, numeric)
  from public, anon, authenticated, service_role;

create or replace function api.open_gift(p_gift_token text)
returns table (
  result_code text,
  reward_available boolean,
  reward_status text,
  reward_name text,
  reward_description text,
  reward_type text,
  customer_value_vnd bigint,
  minimum_spend_vnd bigint,
  applicable_service text,
  discount_percent numeric,
  reward_terms text,
  reward_code text,
  reward_expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign_version_id uuid;
  v_campaign_terms text;
  v_published_at timestamptz;
  v_gift private.gift_entries%rowtype;
  v_prize private.prizes%rowtype;
  v_reward private.rewards%rowtype;
  v_prize_id uuid;
  v_reward_code text;
  v_reward_expires_at timestamptz;
  v_prize_snapshot jsonb;
  v_constraint_name text;
  v_result_code text;
  v_reward_status text;
begin
  if p_gift_token is null
    or char_length(p_gift_token) not between 32 and 128
    or p_gift_token !~ '^[A-Za-z0-9_-]+$'
  then
    return query select
      'INVALID_GIFT'::text,
      false,
      null::text,
      null::text,
      null::text,
      null::text,
      null::bigint,
      null::bigint,
      null::text,
      null::numeric,
      null::text,
      null::text,
      null::timestamptz;
    return;
  end if;

  select ge.campaign_version_id
  into v_campaign_version_id
  from private.gift_entries as ge
  where ge.gift_token = p_gift_token;

  if not found then
    return query select
      'INVALID_GIFT'::text,
      false,
      null::text,
      null::text,
      null::text,
      null::text,
      null::bigint,
      null::bigint,
      null::text,
      null::numeric,
      null::text,
      null::text,
      null::timestamptz;
    return;
  end if;

  -- Every opener for one Campaign Version takes the same lock first. This is a
  -- deliberate low-throughput trade-off that makes Prize inventory races simple.
  select cv.terms, cv.published_at
  into v_campaign_terms, v_published_at
  from private.campaign_versions as cv
  where cv.id = v_campaign_version_id
  for update;

  if not found or v_published_at is null then
    raise exception 'Reward assignment is temporarily unavailable'
      using errcode = 'P0001';
  end if;

  select ge.*
  into v_gift
  from private.gift_entries as ge
  where ge.gift_token = p_gift_token
  for update;

  if not found then
    return query select
      'INVALID_GIFT'::text,
      false,
      null::text,
      null::text,
      null::text,
      null::text,
      null::bigint,
      null::bigint,
      null::text,
      null::numeric,
      null::text,
      null::text,
      null::timestamptz;
    return;
  end if;

  select r.*
  into v_reward
  from private.rewards as r
  where r.gift_entry_id = v_gift.id;

  if v_gift.status = 'CANCELLED' then
    return query select
      'GIFT_CANCELLED'::text,
      false,
      null::text,
      null::text,
      null::text,
      null::text,
      null::bigint,
      null::bigint,
      null::text,
      null::numeric,
      null::text,
      null::text,
      null::timestamptz;
    return;
  end if;

  if found then
    if v_gift.status <> 'OPENED' then
      raise exception 'Reward assignment is temporarily unavailable'
        using errcode = 'P0001';
    end if;

    v_result_code := 'ALREADY_OPENED';
  else
    if v_gift.status <> 'ELIGIBLE' then
      raise exception 'Reward assignment is temporarily unavailable'
        using errcode = 'P0001';
    end if;

    if v_gift.open_expires_at is not null
      and pg_catalog.statement_timestamp() > v_gift.open_expires_at
    then
      return query select
        'OPEN_WINDOW_EXPIRED'::text,
        false,
        null::text,
        null::text,
        null::text,
        null::text,
        null::bigint,
        null::bigint,
        null::text,
        null::numeric,
        null::text,
        null::text,
        null::timestamptz;
      return;
    end if;

    v_prize_id := private.select_weighted_prize(
      v_campaign_version_id,
      pg_catalog.random()::numeric
    );

    select p.*
    into v_prize
    from private.prizes as p
    where p.id = v_prize_id
      and p.campaign_version_id = v_campaign_version_id
      and p.active
      and (
        p.max_quantity is null
        or p.issued_quantity < p.max_quantity
      )
    for update;

    if not found then
      raise exception 'Reward assignment is temporarily unavailable'
        using errcode = 'P0001';
    end if;

    v_reward_expires_at := pg_catalog.statement_timestamp()
      + pg_catalog.make_interval(days => v_prize.expiry_days);

    v_prize_snapshot := pg_catalog.jsonb_build_object(
      'name', v_prize.name,
      'type', v_prize.type,
      'customer_description', v_prize.customer_description,
      'customer_value_vnd', v_prize.customer_value_vnd,
      'discount_percent', v_prize.discount_percent,
      'minimum_spend_vnd', v_prize.minimum_spend_vnd,
      'applicable_service', v_prize.applicable_service,
      'campaign_terms', v_campaign_terms,
      'expiry_days', v_prize.expiry_days
    );

    for v_attempt in 1..5 loop
      v_reward_code := 'CHIC-' || upper(
        substr(
          pg_catalog.encode(extensions.gen_random_bytes(8), 'hex'),
          1,
          12
        )
      );

      begin
        insert into private.rewards (
          gift_entry_id,
          prize_id,
          reward_code,
          snapshot_version,
          prize_snapshot,
          expires_at
        )
        values (
          v_gift.id,
          v_prize.id,
          v_reward_code,
          1,
          v_prize_snapshot,
          v_reward_expires_at
        )
        returning * into v_reward;

        exit;
      exception
        when unique_violation then
          get stacked diagnostics v_constraint_name = constraint_name;

          if v_constraint_name <> 'rewards_reward_code_key' then
            raise;
          end if;
      end;
    end loop;

    if v_reward.id is null then
      raise exception 'Reward Code generation failed safely; retry the request'
        using errcode = '40001';
    end if;

    update private.prizes
    set issued_quantity = issued_quantity + 1,
        updated_at = pg_catalog.statement_timestamp()
    where id = v_prize.id
      and (
        max_quantity is null
        or issued_quantity < max_quantity
      );

    if not found then
      raise exception 'Reward assignment is temporarily unavailable'
        using errcode = '40001';
    end if;

    update private.gift_entries
    set status = 'OPENED',
        opened_at = pg_catalog.statement_timestamp()
    where id = v_gift.id
      and status = 'ELIGIBLE';

    if not found then
      raise exception 'Reward assignment is temporarily unavailable'
        using errcode = '40001';
    end if;

    insert into private.audit_logs (
      action,
      branch_id,
      entity_type,
      entity_id,
      bill_code_normalized,
      new_data,
      metadata
    )
    values (
      'OPEN_GIFT',
      v_gift.branch_id,
      'REWARD',
      v_reward.id,
      v_gift.bill_code_normalized,
      pg_catalog.jsonb_build_object(
        'gift_entry_id', v_gift.id,
        'prize_id', v_prize.id,
        'reward_code', v_reward.reward_code,
        'reward_expires_at', v_reward.expires_at
      ),
      pg_catalog.jsonb_build_object('source', 'PUBLIC_GIFT_TOKEN')
    );

    v_result_code := 'OPENED_NOW';
  end if;

  v_reward_status := case
    when v_reward.redeemed_at is not null then 'REDEEMED'
    when pg_catalog.statement_timestamp() > v_reward.expires_at then 'EXPIRED'
    else 'AVAILABLE'
  end;

  return query select
    v_result_code,
    true,
    v_reward_status,
    v_reward.prize_snapshot ->> 'name',
    v_reward.prize_snapshot ->> 'customer_description',
    v_reward.prize_snapshot ->> 'type',
    (v_reward.prize_snapshot ->> 'customer_value_vnd')::bigint,
    (v_reward.prize_snapshot ->> 'minimum_spend_vnd')::bigint,
    v_reward.prize_snapshot ->> 'applicable_service',
    (v_reward.prize_snapshot ->> 'discount_percent')::numeric,
    v_reward.prize_snapshot ->> 'campaign_terms',
    v_reward.reward_code,
    v_reward.expires_at;
end;
$$;

comment on function api.open_gift(text) is
  'Atomically opens one issued Gift and returns only its customer-safe Reward snapshot; repeated calls return the same Reward.';

revoke all on function api.open_gift(text)
  from public, anon, authenticated, service_role;

grant execute on function api.open_gift(text) to anon, authenticated;
