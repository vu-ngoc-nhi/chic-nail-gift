-- CHIC GIFT Phase 5A: Admin-only Campaign, Version, Prize, and lifecycle management.
-- Internal tables remain private; browser access is limited to authenticated Admin RPCs.

alter table private.audit_logs
  drop constraint audit_logs_action_allowed;

alter table private.audit_logs
  add constraint audit_logs_action_allowed check (
    action in (
      'LOGIN',
      'CREATE_GIFT',
      'DUPLICATE_ATTEMPT',
      'AMOUNT_MISMATCH',
      'GENERATE_QR',
      'OPEN_GIFT',
      'REDEEM_GIFT',
      'EXPIRED_REDEMPTION_ATTEMPT',
      'CREATE_CAMPAIGN',
      'CREATE_CAMPAIGN_VERSION',
      'EDIT_CAMPAIGN',
      'PUBLISH_CAMPAIGN',
      'ACTIVATE_CAMPAIGN',
      'PAUSE_CAMPAIGN',
      'RESUME_CAMPAIGN',
      'END_CAMPAIGN',
      'ARCHIVE_CAMPAIGN',
      'CREATE_PRIZE',
      'EDIT_PRIZE',
      'ADMIN_OVERRIDE',
      'CANCEL_GIFT',
      'EXTEND_REWARD_EXPIRY',
      'CORRECT_BILL_AMOUNT',
      'ADMIN_NOTE',
      'INVENTORY_ISSUE'
    )
  );

create or replace function private.current_admin_context()
returns table (
  actor_id uuid,
  branch_id uuid,
  actor_role private.staff_role
)
language sql
stable
security definer
set search_path = ''
as $$
  select sp.id, sp.branch_id, sp.role
  from private.staff_profiles as sp
  join private.branches as b on b.id = sp.branch_id
  where sp.id = (select auth.uid())
    and sp.active
    and b.active
    and sp.role = 'ADMIN';
$$;

comment on function private.current_admin_context() is
  'Resolves the authenticated active Admin and branch from server-owned Staff data.';

revoke all on function private.current_admin_context()
  from public, anon, authenticated, service_role;

create or replace function private.validate_admin_campaign_version(
  p_campaign_id uuid,
  p_campaign_version_id uuid,
  p_branch_id uuid
)
returns table (
  valid boolean,
  issues text[],
  prize_count integer,
  normal_prize_count integer,
  fallback_count integer,
  fallback_valid boolean
)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_campaign private.campaigns%rowtype;
  v_version private.campaign_versions%rowtype;
  v_prize_count integer;
  v_normal_count integer;
  v_fallback_count integer;
  v_fallback_valid boolean;
  v_issues text[] := array[]::text[];
begin
  select c.*
  into v_campaign
  from private.campaigns as c
  where c.id = p_campaign_id
    and c.branch_id = p_branch_id;

  if not found then
    return query select false, array['CAMPAIGN_NOT_FOUND']::text[], 0, 0, 0, false;
    return;
  end if;

  select cv.*
  into v_version
  from private.campaign_versions as cv
  where cv.id = p_campaign_version_id
    and cv.campaign_id = p_campaign_id;

  if not found then
    return query select false, array['VERSION_NOT_FOUND']::text[], 0, 0, 0, false;
    return;
  end if;

  select
    count(*)::integer,
    count(*) filter (where p.active and not p.is_fallback)::integer,
    count(*) filter (where p.is_fallback)::integer,
    coalesce(bool_and(p.active and p.max_quantity is null) filter (where p.is_fallback), false)
  into v_prize_count, v_normal_count, v_fallback_count, v_fallback_valid
  from private.prizes as p
  where p.campaign_version_id = p_campaign_version_id;

  if v_campaign.end_at <= v_campaign.start_at then
    v_issues := array_append(v_issues, 'INVALID_DATES');
  end if;
  if v_normal_count = 0 then
    v_issues := array_append(v_issues, 'NORMAL_PRIZE_REQUIRED');
  end if;
  if v_fallback_count = 0 then
    v_issues := array_append(v_issues, 'FALLBACK_REQUIRED');
  elsif v_fallback_count > 1 then
    v_issues := array_append(v_issues, 'MULTIPLE_FALLBACKS');
  elsif not v_fallback_valid then
    v_issues := array_append(v_issues, 'FALLBACK_MUST_BE_ACTIVE_UNLIMITED');
  end if;

  return query select
    cardinality(v_issues) = 0,
    v_issues,
    v_prize_count,
    v_normal_count,
    v_fallback_count,
    v_fallback_valid;
end;
$$;

revoke all on function private.validate_admin_campaign_version(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function api.list_admin_campaigns()
returns table (
  campaign_id uuid,
  campaign_name text,
  campaign_status text,
  start_at timestamptz,
  end_at timestamptz,
  current_version_id uuid,
  current_version_number integer,
  minimum_bill_vnd bigint,
  published_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;

  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.name,
    c.status::text,
    c.start_at,
    c.end_at,
    c.current_version_id,
    cv.version_number,
    cv.min_bill_vnd,
    cv.published_at,
    c.created_at,
    c.updated_at
  from private.campaigns as c
  left join private.campaign_versions as cv on cv.id = c.current_version_id
  where c.branch_id = v_branch_id
  order by c.updated_at desc, c.created_at desc;
end;
$$;

create or replace function api.get_admin_campaign(p_campaign_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_result jsonb;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;

  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select pg_catalog.jsonb_build_object(
    'campaign_id', c.id,
    'name', c.name,
    'status', c.status,
    'start_at', c.start_at,
    'end_at', c.end_at,
    'current_version_id', c.current_version_id,
    'created_at', c.created_at,
    'updated_at', c.updated_at,
    'version', case when cv.id is null then null else pg_catalog.jsonb_build_object(
      'campaign_version_id', cv.id,
      'version_number', cv.version_number,
      'min_bill_vnd', cv.min_bill_vnd,
      'gift_open_deadline_hours', cv.gift_open_deadline_hours,
      'headline', cv.headline,
      'description', cv.description,
      'terms', cv.terms,
      'published_at', cv.published_at,
      'is_current', cv.id = c.current_version_id,
      'prizes', coalesce(prizes.items, '[]'::jsonb)
    ) end
  )
  into v_result
  from private.campaigns as c
  left join lateral (
    select candidate.*
    from private.campaign_versions as candidate
    where candidate.campaign_id = c.id
    order by candidate.version_number desc
    limit 1
  ) as cv on true
  left join lateral (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'prize_id', p.id,
        'name', p.name,
        'type', p.type,
        'customer_description', p.customer_description,
        'customer_value_vnd', p.customer_value_vnd,
        'estimated_chic_cost_vnd', p.estimated_chic_cost_vnd,
        'discount_percent', p.discount_percent,
        'minimum_spend_vnd', p.minimum_spend_vnd,
        'applicable_service', p.applicable_service,
        'expiry_days', p.expiry_days,
        'weight', p.weight,
        'max_quantity', p.max_quantity,
        'issued_quantity', p.issued_quantity,
        'is_fallback', p.is_fallback,
        'active', p.active
      ) order by p.is_fallback, p.created_at, p.id
    ) as items
    from private.prizes as p
    where p.campaign_version_id = cv.id
  ) as prizes on true
  where c.id = p_campaign_id
    and c.branch_id = v_branch_id;

  if v_result is null then
    raise exception 'Campaign not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

create or replace function api.create_campaign_draft(
  p_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_min_bill_vnd bigint,
  p_gift_open_deadline_hours integer,
  p_headline text,
  p_description text,
  p_terms text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_campaign_id uuid;
  v_version_id uuid;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  if nullif(btrim(p_name), '') is null or nullif(btrim(p_headline), '') is null then
    raise exception 'Campaign name and headline are required' using errcode = '23514';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'Campaign end must be after start' using errcode = '23514';
  end if;
  if p_min_bill_vnd is null or p_min_bill_vnd < 0 then
    raise exception 'Minimum Bill must be a non-negative integer VND amount' using errcode = '23514';
  end if;
  if p_gift_open_deadline_hours is null or p_gift_open_deadline_hours <= 0 then
    raise exception 'Gift opening deadline must be positive' using errcode = '23514';
  end if;

  insert into private.campaigns (
    branch_id, name, status, start_at, end_at, created_by
  ) values (
    v_branch_id, btrim(p_name), 'DRAFT', p_start_at, p_end_at, v_actor_id
  ) returning id into v_campaign_id;

  insert into private.campaign_versions (
    campaign_id, version_number, min_bill_vnd, gift_open_deadline_hours,
    headline, description, terms, created_by
  ) values (
    v_campaign_id, 1, p_min_bill_vnd, p_gift_open_deadline_hours,
    btrim(p_headline), coalesce(p_description, ''), coalesce(p_terms, ''), v_actor_id
  ) returning id into v_version_id;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, new_data
  ) values
  (
    'CREATE_CAMPAIGN', v_actor_id, v_actor_role, v_branch_id, 'CAMPAIGN', v_campaign_id,
    pg_catalog.jsonb_build_object('name', btrim(p_name), 'status', 'DRAFT', 'start_at', p_start_at, 'end_at', p_end_at)
  ),
  (
    'CREATE_CAMPAIGN_VERSION', v_actor_id, v_actor_role, v_branch_id, 'CAMPAIGN_VERSION', v_version_id,
    pg_catalog.jsonb_build_object('campaign_id', v_campaign_id, 'version_number', 1, 'published', false)
  );

  return pg_catalog.jsonb_build_object(
    'campaign_id', v_campaign_id,
    'campaign_version_id', v_version_id,
    'status', 'DRAFT',
    'version_number', 1
  );
end;
$$;

create or replace function api.update_campaign_draft(
  p_campaign_id uuid,
  p_campaign_version_id uuid,
  p_name text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_min_bill_vnd bigint,
  p_gift_open_deadline_hours integer,
  p_headline text,
  p_description text,
  p_terms text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_campaign private.campaigns%rowtype;
  v_version private.campaign_versions%rowtype;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select c.* into v_campaign
  from private.campaigns as c
  where c.id = p_campaign_id and c.branch_id = v_branch_id
  for update;
  if not found then
    raise exception 'Campaign not found' using errcode = 'P0002';
  end if;
  if v_campaign.status in ('ACTIVE', 'ENDED', 'ARCHIVED') then
    raise exception 'Campaign cannot be edited in its current status' using errcode = '23514';
  end if;

  select cv.* into v_version
  from private.campaign_versions as cv
  where cv.id = p_campaign_version_id and cv.campaign_id = p_campaign_id
  for update;
  if not found then
    raise exception 'Campaign Version not found' using errcode = 'P0002';
  end if;
  if v_version.published_at is not null then
    raise exception 'Published Campaign Versions are immutable' using errcode = '23514';
  end if;

  if nullif(btrim(p_name), '') is null or nullif(btrim(p_headline), '') is null then
    raise exception 'Campaign name and headline are required' using errcode = '23514';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'Campaign end must be after start' using errcode = '23514';
  end if;
  if p_min_bill_vnd is null or p_min_bill_vnd < 0 then
    raise exception 'Minimum Bill must be a non-negative integer VND amount' using errcode = '23514';
  end if;
  if p_gift_open_deadline_hours is null or p_gift_open_deadline_hours <= 0 then
    raise exception 'Gift opening deadline must be positive' using errcode = '23514';
  end if;

  update private.campaigns
  set name = btrim(p_name), start_at = p_start_at, end_at = p_end_at, updated_at = now()
  where id = p_campaign_id;

  update private.campaign_versions
  set min_bill_vnd = p_min_bill_vnd,
      gift_open_deadline_hours = p_gift_open_deadline_hours,
      headline = btrim(p_headline),
      description = coalesce(p_description, ''),
      terms = coalesce(p_terms, '')
  where id = p_campaign_version_id;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, old_data, new_data
  ) values (
    'EDIT_CAMPAIGN', v_actor_id, v_actor_role, v_branch_id, 'CAMPAIGN_VERSION', p_campaign_version_id,
    pg_catalog.jsonb_build_object(
      'name', v_campaign.name, 'start_at', v_campaign.start_at, 'end_at', v_campaign.end_at,
      'min_bill_vnd', v_version.min_bill_vnd, 'gift_open_deadline_hours', v_version.gift_open_deadline_hours,
      'headline', v_version.headline, 'description', v_version.description, 'terms', v_version.terms
    ),
    pg_catalog.jsonb_build_object(
      'name', btrim(p_name), 'start_at', p_start_at, 'end_at', p_end_at,
      'min_bill_vnd', p_min_bill_vnd, 'gift_open_deadline_hours', p_gift_open_deadline_hours,
      'headline', btrim(p_headline), 'description', coalesce(p_description, ''), 'terms', coalesce(p_terms, '')
    )
  );

  return pg_catalog.jsonb_build_object(
    'campaign_id', p_campaign_id,
    'campaign_version_id', p_campaign_version_id,
    'saved', true
  );
end;
$$;

create or replace function api.save_draft_prize(
  p_campaign_id uuid,
  p_campaign_version_id uuid,
  p_prize_id uuid,
  p_name text,
  p_type text,
  p_customer_description text,
  p_customer_value_vnd bigint,
  p_estimated_chic_cost_vnd bigint,
  p_discount_percent numeric,
  p_minimum_spend_vnd bigint,
  p_applicable_service text,
  p_expiry_days integer,
  p_weight bigint,
  p_max_quantity integer,
  p_is_fallback boolean,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_campaign_status private.campaign_status;
  v_published_at timestamptz;
  v_prize private.prizes%rowtype;
  v_prize_id uuid;
  v_type private.prize_type;
  v_action text;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select c.status, cv.published_at
  into v_campaign_status, v_published_at
  from private.campaigns as c
  join private.campaign_versions as cv on cv.campaign_id = c.id
  where c.id = p_campaign_id
    and c.branch_id = v_branch_id
    and cv.id = p_campaign_version_id
  for update of c, cv;
  if not found then
    raise exception 'Campaign Version not found' using errcode = 'P0002';
  end if;
  if v_published_at is not null or v_campaign_status in ('ACTIVE', 'ENDED', 'ARCHIVED') then
    raise exception 'Only an unpublished Campaign Version may change Prizes' using errcode = '23514';
  end if;

  begin
    v_type := p_type::private.prize_type;
  exception when invalid_text_representation then
    raise exception 'Unsupported Prize type' using errcode = '23514';
  end;

  if nullif(btrim(p_name), '') is null or nullif(btrim(p_customer_description), '') is null then
    raise exception 'Prize name and customer description are required' using errcode = '23514';
  end if;
  if p_customer_value_vnd is null or p_customer_value_vnd < 0
    or p_estimated_chic_cost_vnd is null or p_estimated_chic_cost_vnd < 0
    or p_minimum_spend_vnd is null or p_minimum_spend_vnd < 0 then
    raise exception 'Prize VND amounts must be non-negative integers' using errcode = '23514';
  end if;
  if p_expiry_days is null or p_expiry_days <= 0 then
    raise exception 'Prize expiry days must be positive' using errcode = '23514';
  end if;
  if p_weight is null or p_weight <= 0 then
    raise exception 'Prize weight must be positive' using errcode = '23514';
  end if;
  if p_max_quantity is not null and p_max_quantity <= 0 then
    raise exception 'Maximum quantity must be positive or unlimited' using errcode = '23514';
  end if;
  if coalesce(p_is_fallback, false) and p_max_quantity is not null then
    raise exception 'Fallback Prize must use unlimited inventory' using errcode = '23514';
  end if;
  if v_type = 'PERCENT_DISCOUNT' and (
    p_discount_percent is null or p_discount_percent <= 0 or p_discount_percent > 100
  ) then
    raise exception 'Percentage discount must be greater than 0 and at most 100' using errcode = '23514';
  end if;
  if v_type <> 'PERCENT_DISCOUNT' and p_discount_percent is not null then
    raise exception 'Discount percent is only valid for a percentage discount Prize' using errcode = '23514';
  end if;

  if p_prize_id is null then
    insert into private.prizes (
      campaign_version_id, name, type, customer_description,
      customer_value_vnd, estimated_chic_cost_vnd, discount_percent,
      minimum_spend_vnd, applicable_service, expiry_days, weight,
      max_quantity, is_fallback, active
    ) values (
      p_campaign_version_id, btrim(p_name), v_type, btrim(p_customer_description),
      p_customer_value_vnd, p_estimated_chic_cost_vnd, p_discount_percent,
      p_minimum_spend_vnd, nullif(btrim(p_applicable_service), ''), p_expiry_days,
      case when coalesce(p_is_fallback, false) then 1 else p_weight end,
      p_max_quantity, coalesce(p_is_fallback, false), coalesce(p_active, true)
    ) returning id into v_prize_id;
    v_action := 'CREATE_PRIZE';
  else
    select p.* into v_prize
    from private.prizes as p
    where p.id = p_prize_id and p.campaign_version_id = p_campaign_version_id
    for update;
    if not found then
      raise exception 'Prize not found' using errcode = 'P0002';
    end if;
    if v_prize.issued_quantity <> 0 then
      raise exception 'Issued Prize history cannot be changed' using errcode = '23514';
    end if;

    update private.prizes
    set name = btrim(p_name),
        type = v_type,
        customer_description = btrim(p_customer_description),
        customer_value_vnd = p_customer_value_vnd,
        estimated_chic_cost_vnd = p_estimated_chic_cost_vnd,
        discount_percent = p_discount_percent,
        minimum_spend_vnd = p_minimum_spend_vnd,
        applicable_service = nullif(btrim(p_applicable_service), ''),
        expiry_days = p_expiry_days,
        weight = case when coalesce(p_is_fallback, false) then 1 else p_weight end,
        max_quantity = p_max_quantity,
        is_fallback = coalesce(p_is_fallback, false),
        active = coalesce(p_active, true),
        updated_at = now()
    where id = p_prize_id;
    v_prize_id := p_prize_id;
    v_action := 'EDIT_PRIZE';
  end if;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, old_data, new_data
  ) values (
    v_action, v_actor_id, v_actor_role, v_branch_id, 'PRIZE', v_prize_id,
    case when p_prize_id is null then null else to_jsonb(v_prize) end,
    pg_catalog.jsonb_build_object(
      'campaign_version_id', p_campaign_version_id,
      'name', btrim(p_name),
      'type', v_type,
      'customer_value_vnd', p_customer_value_vnd,
      'estimated_chic_cost_vnd', p_estimated_chic_cost_vnd,
      'minimum_spend_vnd', p_minimum_spend_vnd,
      'expiry_days', p_expiry_days,
      'weight', case when coalesce(p_is_fallback, false) then 1 else p_weight end,
      'max_quantity', p_max_quantity,
      'is_fallback', coalesce(p_is_fallback, false),
      'active', coalesce(p_active, true)
    )
  );

  return pg_catalog.jsonb_build_object('prize_id', v_prize_id, 'saved', true);
end;
$$;

create or replace function api.delete_draft_prize(
  p_campaign_id uuid,
  p_campaign_version_id uuid,
  p_prize_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_prize private.prizes%rowtype;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select p.* into v_prize
  from private.prizes as p
  join private.campaign_versions as cv on cv.id = p.campaign_version_id
  join private.campaigns as c on c.id = cv.campaign_id
  where p.id = p_prize_id
    and p.campaign_version_id = p_campaign_version_id
    and cv.campaign_id = p_campaign_id
    and cv.published_at is null
    and c.branch_id = v_branch_id
    and c.status not in ('ACTIVE', 'ENDED', 'ARCHIVED')
  for update of p;
  if not found then
    raise exception 'Editable Draft Prize not found' using errcode = 'P0002';
  end if;
  if v_prize.issued_quantity <> 0 then
    raise exception 'Issued Prize history cannot be deleted' using errcode = '23514';
  end if;

  delete from private.prizes where id = p_prize_id;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, old_data, metadata
  ) values (
    'EDIT_PRIZE', v_actor_id, v_actor_role, v_branch_id, 'PRIZE', p_prize_id,
    to_jsonb(v_prize), pg_catalog.jsonb_build_object('operation', 'DELETE_DRAFT_PRIZE')
  );

  return true;
end;
$$;

create or replace function api.validate_campaign_version(
  p_campaign_id uuid,
  p_campaign_version_id uuid
)
returns table (
  valid boolean,
  issues text[],
  prize_count integer,
  normal_prize_count integer,
  fallback_count integer,
  fallback_valid boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  return query
  select validation.valid, validation.issues, validation.prize_count,
    validation.normal_prize_count, validation.fallback_count, validation.fallback_valid
  from private.validate_admin_campaign_version(
    p_campaign_id, p_campaign_version_id, v_branch_id
  ) as validation;
end;
$$;

create or replace function api.publish_campaign_version(
  p_campaign_id uuid,
  p_campaign_version_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_campaign private.campaigns%rowtype;
  v_version private.campaign_versions%rowtype;
  v_validation record;
  v_published_at timestamptz := pg_catalog.statement_timestamp();
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select c.* into v_campaign
  from private.campaigns as c
  where c.id = p_campaign_id and c.branch_id = v_branch_id
  for update;
  if not found then
    raise exception 'Campaign not found' using errcode = 'P0002';
  end if;
  if v_campaign.status in ('ACTIVE', 'ENDED', 'ARCHIVED') then
    raise exception 'Campaign must not be active or closed while publishing' using errcode = '23514';
  end if;

  select cv.* into v_version
  from private.campaign_versions as cv
  where cv.id = p_campaign_version_id and cv.campaign_id = p_campaign_id
  for update;
  if not found then
    raise exception 'Campaign Version not found' using errcode = 'P0002';
  end if;
  if v_version.published_at is not null then
    raise exception 'Campaign Version is already published' using errcode = '23514';
  end if;

  select * into v_validation
  from private.validate_admin_campaign_version(p_campaign_id, p_campaign_version_id, v_branch_id);
  if not v_validation.valid then
    raise exception 'Campaign Version is not publishable: %', array_to_string(v_validation.issues, ', ')
      using errcode = '23514';
  end if;

  update private.campaign_versions
  set published_at = v_published_at
  where id = p_campaign_version_id;

  update private.campaigns
  set current_version_id = p_campaign_version_id, updated_at = now()
  where id = p_campaign_id;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, new_data
  ) values (
    'PUBLISH_CAMPAIGN', v_actor_id, v_actor_role, v_branch_id,
    'CAMPAIGN_VERSION', p_campaign_version_id,
    pg_catalog.jsonb_build_object(
      'campaign_id', p_campaign_id,
      'version_number', v_version.version_number,
      'published_at', v_published_at,
      'prize_count', v_validation.prize_count,
      'normal_prize_count', v_validation.normal_prize_count
    )
  );

  return pg_catalog.jsonb_build_object(
    'campaign_id', p_campaign_id,
    'campaign_version_id', p_campaign_version_id,
    'published_at', v_published_at,
    'status', v_campaign.status
  );
end;
$$;

create or replace function api.create_new_campaign_version(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_campaign private.campaigns%rowtype;
  v_source private.campaign_versions%rowtype;
  v_new_version_id uuid;
  v_new_version_number integer;
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select c.* into v_campaign
  from private.campaigns as c
  where c.id = p_campaign_id and c.branch_id = v_branch_id
  for update;
  if not found then
    raise exception 'Campaign not found' using errcode = 'P0002';
  end if;
  if v_campaign.status in ('ACTIVE', 'ENDED', 'ARCHIVED') then
    raise exception 'Pause the Campaign before creating a new Version' using errcode = '23514';
  end if;
  if v_campaign.current_version_id is null then
    raise exception 'A published current Version is required for cloning' using errcode = '23514';
  end if;
  if exists (
    select 1 from private.campaign_versions as cv
    where cv.campaign_id = p_campaign_id and cv.published_at is null
  ) then
    raise exception 'An unpublished Campaign Version already exists' using errcode = '23514';
  end if;

  select cv.* into v_source
  from private.campaign_versions as cv
  where cv.id = v_campaign.current_version_id
    and cv.campaign_id = p_campaign_id
    and cv.published_at is not null;
  if not found then
    raise exception 'Published current Campaign Version not found' using errcode = 'P0002';
  end if;

  select coalesce(max(cv.version_number), 0) + 1
  into v_new_version_number
  from private.campaign_versions as cv
  where cv.campaign_id = p_campaign_id;

  insert into private.campaign_versions (
    campaign_id, version_number, min_bill_vnd, gift_open_deadline_hours,
    headline, description, terms, created_by
  ) values (
    p_campaign_id, v_new_version_number, v_source.min_bill_vnd,
    v_source.gift_open_deadline_hours, v_source.headline, v_source.description,
    v_source.terms, v_actor_id
  ) returning id into v_new_version_id;

  insert into private.prizes (
    campaign_version_id, name, type, customer_description,
    customer_value_vnd, estimated_chic_cost_vnd, discount_percent,
    minimum_spend_vnd, applicable_service, expiry_days, weight,
    max_quantity, issued_quantity, is_fallback, active
  )
  select
    v_new_version_id, p.name, p.type, p.customer_description,
    p.customer_value_vnd, p.estimated_chic_cost_vnd, p.discount_percent,
    p.minimum_spend_vnd, p.applicable_service, p.expiry_days, p.weight,
    p.max_quantity, 0, p.is_fallback, p.active
  from private.prizes as p
  where p.campaign_version_id = v_source.id;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, new_data, metadata
  ) values (
    'CREATE_CAMPAIGN_VERSION', v_actor_id, v_actor_role, v_branch_id,
    'CAMPAIGN_VERSION', v_new_version_id,
    pg_catalog.jsonb_build_object(
      'campaign_id', p_campaign_id,
      'version_number', v_new_version_number,
      'published', false
    ),
    pg_catalog.jsonb_build_object('cloned_from_version_id', v_source.id)
  );

  return pg_catalog.jsonb_build_object(
    'campaign_id', p_campaign_id,
    'campaign_version_id', v_new_version_id,
    'version_number', v_new_version_number,
    'published_at', null
  );
end;
$$;

create or replace function api.set_campaign_lifecycle(
  p_campaign_id uuid,
  p_action text,
  p_confirmed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid;
  v_branch_id uuid;
  v_actor_role private.staff_role;
  v_campaign private.campaigns%rowtype;
  v_next_status private.campaign_status;
  v_audit_action text;
  v_now timestamptz := pg_catalog.statement_timestamp();
begin
  select context.actor_id, context.branch_id, context.actor_role
  into v_actor_id, v_branch_id, v_actor_role
  from private.current_admin_context() as context;
  if not found then
    raise exception 'Active Admin authorization required' using errcode = '42501';
  end if;

  select c.* into v_campaign
  from private.campaigns as c
  where c.id = p_campaign_id and c.branch_id = v_branch_id
  for update;
  if not found then
    raise exception 'Campaign not found' using errcode = 'P0002';
  end if;

  case upper(coalesce(p_action, ''))
    when 'ACTIVATE' then
      if not coalesce(p_confirmed, false) then
        raise exception 'Activation confirmation required' using errcode = '23514';
      end if;
      if v_campaign.status not in ('DRAFT', 'SCHEDULED') then
        raise exception 'Only a Draft or Scheduled Campaign can be activated' using errcode = '23514';
      end if;
      if v_campaign.current_version_id is null or not exists (
        select 1 from private.campaign_versions as cv
        where cv.id = v_campaign.current_version_id
          and cv.campaign_id = v_campaign.id
          and cv.published_at is not null
      ) then
        raise exception 'A published current Campaign Version is required' using errcode = '23514';
      end if;
      if v_now < v_campaign.start_at or v_now > v_campaign.end_at then
        raise exception 'Campaign date window is not currently active' using errcode = '23514';
      end if;
      if exists (
        select 1 from private.campaigns as active_campaign
        where active_campaign.branch_id = v_branch_id
          and active_campaign.status = 'ACTIVE'
          and active_campaign.id <> p_campaign_id
      ) then
        raise exception 'Another Campaign is already active for this branch' using errcode = '23514';
      end if;
      v_next_status := 'ACTIVE';
      v_audit_action := 'ACTIVATE_CAMPAIGN';
    when 'PAUSE' then
      if v_campaign.status <> 'ACTIVE' then
        raise exception 'Only an active Campaign can be paused' using errcode = '23514';
      end if;
      v_next_status := 'PAUSED';
      v_audit_action := 'PAUSE_CAMPAIGN';
    when 'RESUME' then
      if v_campaign.status <> 'PAUSED' then
        raise exception 'Only a paused Campaign can be resumed' using errcode = '23514';
      end if;
      if v_now < v_campaign.start_at or v_now > v_campaign.end_at then
        raise exception 'Campaign date window is not currently active' using errcode = '23514';
      end if;
      if v_campaign.current_version_id is null then
        raise exception 'A published current Campaign Version is required' using errcode = '23514';
      end if;
      if exists (
        select 1 from private.campaigns as active_campaign
        where active_campaign.branch_id = v_branch_id
          and active_campaign.status = 'ACTIVE'
          and active_campaign.id <> p_campaign_id
      ) then
        raise exception 'Another Campaign is already active for this branch' using errcode = '23514';
      end if;
      v_next_status := 'ACTIVE';
      v_audit_action := 'RESUME_CAMPAIGN';
    when 'END' then
      if not coalesce(p_confirmed, false) then
        raise exception 'End confirmation required' using errcode = '23514';
      end if;
      if v_campaign.status in ('ENDED', 'ARCHIVED') then
        raise exception 'Campaign is already closed' using errcode = '23514';
      end if;
      v_next_status := 'ENDED';
      v_audit_action := 'END_CAMPAIGN';
    when 'ARCHIVE' then
      if not coalesce(p_confirmed, false) then
        raise exception 'Archive confirmation required' using errcode = '23514';
      end if;
      if v_campaign.status <> 'ENDED' then
        raise exception 'Only an ended Campaign can be archived' using errcode = '23514';
      end if;
      v_next_status := 'ARCHIVED';
      v_audit_action := 'ARCHIVE_CAMPAIGN';
    else
      raise exception 'Unsupported Campaign lifecycle action' using errcode = '23514';
  end case;

  update private.campaigns
  set status = v_next_status, updated_at = now()
  where id = p_campaign_id;

  insert into private.audit_logs (
    action, actor_id, actor_role, branch_id, entity_type, entity_id, old_data, new_data
  ) values (
    v_audit_action, v_actor_id, v_actor_role, v_branch_id, 'CAMPAIGN', p_campaign_id,
    pg_catalog.jsonb_build_object('status', v_campaign.status),
    pg_catalog.jsonb_build_object('status', v_next_status)
  );

  return pg_catalog.jsonb_build_object(
    'campaign_id', p_campaign_id,
    'previous_status', v_campaign.status,
    'status', v_next_status
  );
end;
$$;

revoke all on function api.list_admin_campaigns()
  from public, anon, authenticated, service_role;
revoke all on function api.get_admin_campaign(uuid)
  from public, anon, authenticated, service_role;
revoke all on function api.create_campaign_draft(text, timestamptz, timestamptz, bigint, integer, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function api.update_campaign_draft(uuid, uuid, text, timestamptz, timestamptz, bigint, integer, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function api.save_draft_prize(uuid, uuid, uuid, text, text, text, bigint, bigint, numeric, bigint, text, integer, bigint, integer, boolean, boolean)
  from public, anon, authenticated, service_role;
revoke all on function api.delete_draft_prize(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function api.validate_campaign_version(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function api.publish_campaign_version(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function api.create_new_campaign_version(uuid)
  from public, anon, authenticated, service_role;
revoke all on function api.set_campaign_lifecycle(uuid, text, boolean)
  from public, anon, authenticated, service_role;

grant usage on schema api to authenticated;
grant execute on function api.list_admin_campaigns() to authenticated;
grant execute on function api.get_admin_campaign(uuid) to authenticated;
grant execute on function api.create_campaign_draft(text, timestamptz, timestamptz, bigint, integer, text, text, text) to authenticated;
grant execute on function api.update_campaign_draft(uuid, uuid, text, timestamptz, timestamptz, bigint, integer, text, text, text) to authenticated;
grant execute on function api.save_draft_prize(uuid, uuid, uuid, text, text, text, bigint, bigint, numeric, bigint, text, integer, bigint, integer, boolean, boolean) to authenticated;
grant execute on function api.delete_draft_prize(uuid, uuid, uuid) to authenticated;
grant execute on function api.validate_campaign_version(uuid, uuid) to authenticated;
grant execute on function api.publish_campaign_version(uuid, uuid) to authenticated;
grant execute on function api.create_new_campaign_version(uuid) to authenticated;
grant execute on function api.set_campaign_lifecycle(uuid, text, boolean) to authenticated;

comment on function api.list_admin_campaigns() is
  'Lists Campaign summaries for the authenticated active Admin branch.';
comment on function api.get_admin_campaign(uuid) is
  'Returns Admin-only Campaign, latest Version, Prize inventory, and internal cost data.';
comment on function api.create_campaign_draft(text, timestamptz, timestamptz, bigint, integer, text, text, text) is
  'Creates one Draft Campaign and its initial unpublished Version for the Admin branch.';
comment on function api.create_new_campaign_version(uuid) is
  'Clones the current published Version and Prize configuration into a new editable Draft Version.';
