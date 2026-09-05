-- CHIC GIFT Phase 1D: secure Gift creation and customer-safe Gift lookup.
-- Prize selection, Reward creation, redemption, and UI are intentionally excluded.

create or replace function api.create_gift(
  p_bill_code text,
  p_bill_amount_vnd bigint
)
returns table (
  result_code text,
  gift_id uuid,
  bill_code text,
  bill_amount_vnd bigint,
  gift_status text,
  gift_token text,
  created_at timestamptz,
  is_new boolean,
  minimum_bill_vnd bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := (select auth.uid());
  v_actor_role private.staff_role;
  v_branch_id uuid;
  v_bill_code text;
  v_campaign_version_id uuid;
  v_minimum_bill_vnd bigint;
  v_open_expires_at timestamptz;
  v_gift private.gift_entries%rowtype;
  v_token text;
  v_attempt integer;
  v_inserted boolean := false;
begin
  if v_actor_id is null then
    raise exception 'Active Staff or Admin authorization required'
      using errcode = '42501';
  end if;

  select sp.role, sp.branch_id
  into v_actor_role, v_branch_id
  from private.staff_profiles as sp
  join private.branches as b on b.id = sp.branch_id
  where sp.id = v_actor_id
    and sp.active
    and b.active;

  if not found then
    raise exception 'Active Staff or Admin authorization required'
      using errcode = '42501';
  end if;

  if p_bill_code is null then
    return query select
      'INVALID_BILL_CODE'::text,
      null::uuid,
      null::text,
      null::bigint,
      null::text,
      null::text,
      null::timestamptz,
      false,
      null::bigint;
    return;
  end if;

  begin
    v_bill_code := private.normalize_bill_code(p_bill_code);
  exception
    when check_violation then
      return query select
        'INVALID_BILL_CODE'::text,
        null::uuid,
        null::text,
        null::bigint,
        null::text,
        null::text,
        null::timestamptz,
        false,
        null::bigint;
      return;
  end;

  if p_bill_amount_vnd is null or p_bill_amount_vnd <= 0 then
    return query select
      'INVALID_BILL_AMOUNT'::text,
      null::uuid,
      v_bill_code,
      p_bill_amount_vnd,
      null::text,
      null::text,
      null::timestamptz,
      false,
      null::bigint;
    return;
  end if;

  select ge.*
  into v_gift
  from private.gift_entries as ge
  where ge.branch_id = v_branch_id
    and ge.bill_code_normalized = v_bill_code;

  if found then
    select cv.min_bill_vnd
    into v_minimum_bill_vnd
    from private.campaign_versions as cv
    where cv.id = v_gift.campaign_version_id;

    if v_gift.bill_amount_vnd = p_bill_amount_vnd then
      insert into private.audit_logs (
        action,
        actor_id,
        actor_role,
        branch_id,
        entity_type,
        entity_id,
        bill_code_normalized,
        old_data,
        new_data
      )
      values (
        'DUPLICATE_ATTEMPT',
        v_actor_id,
        v_actor_role,
        v_branch_id,
        'GIFT_ENTRY',
        v_gift.id,
        v_bill_code,
        pg_catalog.jsonb_build_object('bill_amount_vnd', v_gift.bill_amount_vnd),
        pg_catalog.jsonb_build_object('bill_amount_vnd', p_bill_amount_vnd)
      );

      return query select
        'EXISTING_GIFT'::text,
        v_gift.id,
        v_gift.bill_code_normalized,
        v_gift.bill_amount_vnd,
        v_gift.status::text,
        v_gift.gift_token,
        v_gift.created_at,
        false,
        v_minimum_bill_vnd;
      return;
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
      new_data
    )
    values (
      'AMOUNT_MISMATCH',
      v_actor_id,
      v_actor_role,
      v_branch_id,
      'GIFT_ENTRY',
      v_gift.id,
      v_bill_code,
      pg_catalog.jsonb_build_object('bill_amount_vnd', v_gift.bill_amount_vnd),
      pg_catalog.jsonb_build_object('bill_amount_vnd', p_bill_amount_vnd)
    );

    return query select
      'AMOUNT_MISMATCH'::text,
      v_gift.id,
      v_gift.bill_code_normalized,
      v_gift.bill_amount_vnd,
      v_gift.status::text,
      null::text,
      v_gift.created_at,
      false,
      v_minimum_bill_vnd;
    return;
  end if;

  select
    cv.id,
    cv.min_bill_vnd,
    case
      when cv.gift_open_deadline_hours is null then null
      else pg_catalog.statement_timestamp()
        + pg_catalog.make_interval(hours => cv.gift_open_deadline_hours)
    end
  into
    v_campaign_version_id,
    v_minimum_bill_vnd,
    v_open_expires_at
  from private.campaigns as c
  join private.campaign_versions as cv
    on cv.id = c.current_version_id
    and cv.campaign_id = c.id
  where c.branch_id = v_branch_id
    and c.status = 'ACTIVE'
    and pg_catalog.statement_timestamp() >= c.start_at
    and pg_catalog.statement_timestamp() <= c.end_at
    and cv.published_at is not null;

  if not found then
    return query select
      'NO_ACTIVE_CAMPAIGN'::text,
      null::uuid,
      v_bill_code,
      p_bill_amount_vnd,
      null::text,
      null::text,
      null::timestamptz,
      false,
      null::bigint;
    return;
  end if;

  if p_bill_amount_vnd < v_minimum_bill_vnd then
    return query select
      'BILL_BELOW_MINIMUM'::text,
      null::uuid,
      v_bill_code,
      p_bill_amount_vnd,
      null::text,
      null::text,
      null::timestamptz,
      false,
      v_minimum_bill_vnd;
    return;
  end if;

  for v_attempt in 1..5 loop
    v_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');

    begin
      insert into private.gift_entries (
        branch_id,
        bill_code_entered,
        bill_amount_vnd,
        campaign_version_id,
        gift_token,
        status,
        open_expires_at,
        created_by
      )
      values (
        v_branch_id,
        v_bill_code,
        p_bill_amount_vnd,
        v_campaign_version_id,
        v_token,
        'ELIGIBLE',
        v_open_expires_at,
        v_actor_id
      )
      on conflict (branch_id, bill_code_normalized) do nothing
      returning * into v_gift;

      v_inserted := found;
    exception
      when unique_violation then
        -- A token or generated UUID collision is exceptionally unlikely; retry safely.
        v_inserted := false;
    end;

    if v_inserted then
      exit;
    end if;

    select ge.*
    into v_gift
    from private.gift_entries as ge
    where ge.branch_id = v_branch_id
      and ge.bill_code_normalized = v_bill_code;

    if found then
      if v_gift.bill_amount_vnd = p_bill_amount_vnd then
        insert into private.audit_logs (
          action,
          actor_id,
          actor_role,
          branch_id,
          entity_type,
          entity_id,
          bill_code_normalized,
          old_data,
          new_data
        )
        values (
          'DUPLICATE_ATTEMPT',
          v_actor_id,
          v_actor_role,
          v_branch_id,
          'GIFT_ENTRY',
          v_gift.id,
          v_bill_code,
          pg_catalog.jsonb_build_object('bill_amount_vnd', v_gift.bill_amount_vnd),
          pg_catalog.jsonb_build_object('bill_amount_vnd', p_bill_amount_vnd)
        );

        return query select
          'EXISTING_GIFT'::text,
          v_gift.id,
          v_gift.bill_code_normalized,
          v_gift.bill_amount_vnd,
          v_gift.status::text,
          v_gift.gift_token,
          v_gift.created_at,
          false,
          v_minimum_bill_vnd;
        return;
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
        new_data
      )
      values (
        'AMOUNT_MISMATCH',
        v_actor_id,
        v_actor_role,
        v_branch_id,
        'GIFT_ENTRY',
        v_gift.id,
        v_bill_code,
        pg_catalog.jsonb_build_object('bill_amount_vnd', v_gift.bill_amount_vnd),
        pg_catalog.jsonb_build_object('bill_amount_vnd', p_bill_amount_vnd)
      );

      return query select
        'AMOUNT_MISMATCH'::text,
        v_gift.id,
        v_gift.bill_code_normalized,
        v_gift.bill_amount_vnd,
        v_gift.status::text,
        null::text,
        v_gift.created_at,
        false,
        v_minimum_bill_vnd;
      return;
    end if;
  end loop;

  if not v_inserted then
    raise exception 'Gift Token generation failed safely; retry the request'
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
    new_data
  )
  values (
    'CREATE_GIFT',
    v_actor_id,
    v_actor_role,
    v_branch_id,
    'GIFT_ENTRY',
    v_gift.id,
    v_bill_code,
    pg_catalog.jsonb_build_object(
      'bill_amount_vnd', v_gift.bill_amount_vnd,
      'campaign_version_id', v_gift.campaign_version_id,
      'gift_status', v_gift.status
    )
  );

  return query select
    'CREATED_GIFT'::text,
    v_gift.id,
    v_gift.bill_code_normalized,
    v_gift.bill_amount_vnd,
    v_gift.status::text,
    v_gift.gift_token,
    v_gift.created_at,
    true,
    v_minimum_bill_vnd;
end;
$$;

comment on function api.create_gift(text, bigint) is
  'Creates or safely recovers one Gift for the signed-in active Staff/Admin branch.';

create or replace function api.get_public_gift(p_gift_token text)
returns table (
  result_code text,
  valid boolean,
  gift_status text,
  may_open boolean,
  campaign_headline text,
  campaign_description text,
  campaign_terms text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gift_status private.gift_status;
  v_open_expires_at timestamptz;
  v_headline text;
  v_description text;
  v_terms text;
  v_may_open boolean;
begin
  if p_gift_token is null
    or char_length(p_gift_token) not between 32 and 128
    or p_gift_token !~ '^[A-Za-z0-9_-]+$'
  then
    return query select
      'INVALID_GIFT'::text,
      false,
      null::text,
      false,
      null::text,
      null::text,
      null::text;
    return;
  end if;

  select
    ge.status,
    ge.open_expires_at,
    cv.headline,
    cv.description,
    cv.terms
  into
    v_gift_status,
    v_open_expires_at,
    v_headline,
    v_description,
    v_terms
  from private.gift_entries as ge
  join private.campaign_versions as cv on cv.id = ge.campaign_version_id
  where ge.gift_token = p_gift_token;

  if not found then
    return query select
      'INVALID_GIFT'::text,
      false,
      null::text,
      false,
      null::text,
      null::text,
      null::text;
    return;
  end if;

  v_may_open := v_gift_status = 'ELIGIBLE'
    and (
      v_open_expires_at is null
      or pg_catalog.statement_timestamp() <= v_open_expires_at
    );

  return query select
    case
      when v_gift_status = 'CANCELLED' then 'GIFT_UNAVAILABLE'
      when v_gift_status = 'OPENED' then 'GIFT_OPENED'
      when v_may_open then 'GIFT_AVAILABLE'
      else 'OPEN_WINDOW_EXPIRED'
    end::text,
    true,
    v_gift_status::text,
    v_may_open,
    case when v_gift_status = 'CANCELLED' then null else v_headline end,
    case when v_gift_status = 'CANCELLED' then null else v_description end,
    case when v_gift_status = 'CANCELLED' then null else v_terms end;
end;
$$;

comment on function api.get_public_gift(text) is
  'Returns only the customer-safe Gift projection for one high-entropy Gift Token.';

revoke all on function api.create_gift(text, bigint)
  from public, anon, authenticated, service_role;
revoke all on function api.get_public_gift(text)
  from public, anon, authenticated, service_role;

grant usage on schema api to anon, authenticated;
grant execute on function api.create_gift(text, bigint) to authenticated;
grant execute on function api.get_public_gift(text) to anon, authenticated;
