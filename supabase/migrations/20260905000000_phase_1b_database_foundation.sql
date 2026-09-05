-- CHIC GIFT Phase 1B: database and authorization foundation.
-- Product operations (create/open/redeem/override) are intentionally excluded.

create schema if not exists private;
create schema if not exists api;

comment on schema private is 'Internal CHIC GIFT data and privileged helpers; do not expose through the Data API.';
comment on schema api is 'Reserved for narrowly scoped, customer-safe and staff-safe API functions.';

revoke all on schema private from public, anon, authenticated;
revoke all on schema api from public, anon, authenticated;

create type private.staff_role as enum ('STAFF', 'ADMIN');
create type private.campaign_status as enum (
  'DRAFT',
  'SCHEDULED',
  'ACTIVE',
  'PAUSED',
  'ENDED',
  'ARCHIVED'
);
create type private.gift_status as enum ('ELIGIBLE', 'OPENED', 'CANCELLED');
create type private.prize_type as enum (
  'CASH_VOUCHER',
  'PERCENT_DISCOUNT',
  'FREE_SERVICE',
  'SERVICE_DISCOUNT',
  'SERVICE_UPGRADE',
  'CUSTOM_REWARD'
);

create or replace function private.normalize_bill_code(p_bill_code text)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_normalized text;
begin
  v_normalized := upper(
    regexp_replace(
      p_bill_code,
      '^[[:space:]]+|[[:space:]]+$',
      '',
      'g'
    )
  );

  if v_normalized = '' then
    raise exception 'Bill Code cannot be empty'
      using errcode = '23514';
  end if;

  if v_normalized ~ '[[:space:]]' then
    raise exception 'Bill Code cannot contain internal whitespace'
      using errcode = '23514';
  end if;

  if char_length(v_normalized) > 100 then
    raise exception 'Bill Code cannot exceed 100 characters'
      using errcode = '23514';
  end if;

  return v_normalized;
end;
$$;

comment on function private.normalize_bill_code(text) is
  'Trims outer whitespace, uppercases Bill Codes, and rejects internal whitespace.';

create table private.branches (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint branches_code_not_blank check (btrim(code) <> ''),
  constraint branches_name_not_blank check (btrim(name) <> '')
);

create table private.staff_profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  branch_id uuid not null references private.branches(id) on delete restrict,
  name text not null,
  role private.staff_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_profiles_name_not_blank check (btrim(name) <> '')
);

create table private.campaigns (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references private.branches(id) on delete restrict,
  name text not null,
  status private.campaign_status not null default 'DRAFT',
  start_at timestamptz not null,
  end_at timestamptz not null,
  current_version_id uuid,
  created_by uuid not null references private.staff_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campaigns_name_not_blank check (btrim(name) <> ''),
  constraint campaigns_date_order check (end_at > start_at),
  constraint campaigns_active_version_required check (
    status <> 'ACTIVE' or current_version_id is not null
  )
);

create unique index campaigns_one_active_per_branch_idx
  on private.campaigns (branch_id)
  where status = 'ACTIVE';

create table private.campaign_versions (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references private.campaigns(id) on delete restrict,
  version_number integer not null,
  min_bill_vnd bigint not null,
  gift_open_deadline_hours integer,
  headline text not null,
  description text not null default '',
  terms text not null default '',
  published_at timestamptz,
  created_by uuid not null references private.staff_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint campaign_versions_number_positive check (version_number > 0),
  constraint campaign_versions_min_bill_nonnegative check (min_bill_vnd >= 0),
  constraint campaign_versions_deadline_positive check (
    gift_open_deadline_hours is null or gift_open_deadline_hours > 0
  ),
  constraint campaign_versions_headline_not_blank check (btrim(headline) <> ''),
  constraint campaign_versions_campaign_number_key unique (campaign_id, version_number),
  constraint campaign_versions_campaign_id_id_key unique (campaign_id, id)
);

alter table private.campaigns
  add constraint campaigns_current_version_belongs_to_campaign_fkey
  foreign key (id, current_version_id)
  references private.campaign_versions (campaign_id, id)
  on delete restrict
  deferrable initially deferred;

create table private.prizes (
  id uuid primary key default gen_random_uuid(),
  campaign_version_id uuid not null references private.campaign_versions(id) on delete restrict,
  name text not null,
  type private.prize_type not null,
  customer_description text not null,
  customer_value_vnd bigint not null default 0,
  estimated_chic_cost_vnd bigint not null default 0,
  discount_percent numeric(5, 2),
  minimum_spend_vnd bigint not null default 0,
  applicable_service text,
  expiry_days integer not null,
  weight bigint not null,
  max_quantity integer,
  issued_quantity integer not null default 0,
  is_fallback boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prizes_name_not_blank check (btrim(name) <> ''),
  constraint prizes_description_not_blank check (btrim(customer_description) <> ''),
  constraint prizes_customer_value_nonnegative check (customer_value_vnd >= 0),
  constraint prizes_estimated_cost_nonnegative check (estimated_chic_cost_vnd >= 0),
  constraint prizes_minimum_spend_nonnegative check (minimum_spend_vnd >= 0),
  constraint prizes_expiry_days_positive check (expiry_days > 0),
  constraint prizes_weight_positive check (weight > 0),
  constraint prizes_max_quantity_positive check (max_quantity is null or max_quantity > 0),
  constraint prizes_issued_quantity_nonnegative check (issued_quantity >= 0),
  constraint prizes_inventory_within_limit check (
    max_quantity is null or issued_quantity <= max_quantity
  ),
  constraint prizes_fallback_unlimited check (
    not is_fallback or max_quantity is null
  ),
  constraint prizes_percentage_value_valid check (
    (
      type = 'PERCENT_DISCOUNT'
      and discount_percent is not null
      and discount_percent > 0
      and discount_percent <= 100
    )
    or
    (type <> 'PERCENT_DISCOUNT' and discount_percent is null)
  )
);

create unique index prizes_one_fallback_per_version_idx
  on private.prizes (campaign_version_id)
  where is_fallback;

create table private.gift_entries (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references private.branches(id) on delete restrict,
  bill_code_entered text not null,
  bill_code_normalized text generated always as (
    private.normalize_bill_code(bill_code_entered)
  ) stored,
  bill_amount_vnd bigint not null,
  campaign_version_id uuid not null references private.campaign_versions(id) on delete restrict,
  gift_token text not null unique,
  status private.gift_status not null default 'ELIGIBLE',
  open_expires_at timestamptz,
  created_by uuid not null references private.staff_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references private.staff_profiles(id) on delete restrict,
  constraint gift_entries_bill_amount_positive check (bill_amount_vnd > 0),
  constraint gift_entries_token_length check (char_length(gift_token) between 32 and 128),
  constraint gift_entries_branch_bill_key unique (branch_id, bill_code_normalized),
  constraint gift_entries_cancellation_pair check (
    (cancelled_at is null and cancelled_by is null)
    or
    (cancelled_at is not null and cancelled_by is not null)
  ),
  constraint gift_entries_status_timestamps_consistent check (
    (status = 'ELIGIBLE' and opened_at is null and cancelled_at is null)
    or
    (status = 'OPENED' and opened_at is not null and cancelled_at is null)
    or
    (status = 'CANCELLED' and cancelled_at is not null)
  )
);

create index gift_entries_campaign_version_idx
  on private.gift_entries (campaign_version_id);

create index gift_entries_created_at_idx
  on private.gift_entries (created_at desc);

create table private.rewards (
  id uuid primary key default gen_random_uuid(),
  gift_entry_id uuid not null unique references private.gift_entries(id) on delete restrict,
  prize_id uuid not null references private.prizes(id) on delete restrict,
  reward_code text not null unique,
  snapshot_version smallint not null default 1,
  prize_snapshot jsonb not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  redeemed_at timestamptz,
  redeemed_by uuid references private.staff_profiles(id) on delete restrict,
  constraint rewards_code_format check (reward_code ~ '^CHIC-[A-Z0-9]{5,16}$'),
  constraint rewards_snapshot_version_positive check (snapshot_version > 0),
  constraint rewards_snapshot_is_object check (jsonb_typeof(prize_snapshot) = 'object'),
  constraint rewards_expiry_after_creation check (expires_at > created_at),
  constraint rewards_redemption_pair check (
    (redeemed_at is null and redeemed_by is null)
    or
    (redeemed_at is not null and redeemed_by is not null)
  )
);

create index rewards_expires_at_idx on private.rewards (expires_at);

create table private.audit_logs (
  id bigint generated always as identity primary key,
  action text not null,
  actor_id uuid references private.staff_profiles(id) on delete restrict,
  actor_role private.staff_role,
  branch_id uuid references private.branches(id) on delete restrict,
  entity_type text not null,
  entity_id uuid,
  bill_code_normalized text,
  old_data jsonb,
  new_data jsonb,
  reason text,
  metadata jsonb,
  request_id uuid,
  created_at timestamptz not null default now(),
  constraint audit_logs_action_allowed check (
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
      'EDIT_CAMPAIGN',
      'PUBLISH_CAMPAIGN',
      'PAUSE_CAMPAIGN',
      'END_CAMPAIGN',
      'CREATE_PRIZE',
      'EDIT_PRIZE',
      'ADMIN_OVERRIDE',
      'CANCEL_GIFT',
      'EXTEND_REWARD_EXPIRY',
      'CORRECT_BILL_AMOUNT',
      'ADMIN_NOTE',
      'INVENTORY_ISSUE'
    )
  ),
  constraint audit_logs_entity_type_allowed check (
    entity_type in (
      'AUTH',
      'BRANCH',
      'STAFF_PROFILE',
      'CAMPAIGN',
      'CAMPAIGN_VERSION',
      'PRIZE',
      'GIFT_ENTRY',
      'REWARD'
    )
  ),
  constraint audit_logs_actor_pair check (
    (actor_id is null and actor_role is null)
    or
    (actor_id is not null and actor_role is not null)
  ),
  constraint audit_logs_old_data_object check (
    old_data is null or jsonb_typeof(old_data) = 'object'
  ),
  constraint audit_logs_new_data_object check (
    new_data is null or jsonb_typeof(new_data) = 'object'
  ),
  constraint audit_logs_metadata_object check (
    metadata is null or jsonb_typeof(metadata) = 'object'
  ),
  constraint audit_logs_override_reason_required check (
    action not in (
      'ADMIN_OVERRIDE',
      'CANCEL_GIFT',
      'EXTEND_REWARD_EXPIRY',
      'CORRECT_BILL_AMOUNT',
      'ADMIN_NOTE'
    )
    or nullif(btrim(reason), '') is not null
  )
);

create index audit_logs_created_at_idx on private.audit_logs (created_at desc);
create index audit_logs_action_created_at_idx on private.audit_logs (action, created_at desc);
create index audit_logs_entity_idx on private.audit_logs (entity_type, entity_id);

create or replace function private.validate_campaign_current_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.current_version_id is not null and not exists (
    select 1
    from private.campaign_versions as cv
    where cv.id = new.current_version_id
      and cv.campaign_id = new.id
      and cv.published_at is not null
  ) then
    raise exception 'Current Campaign Version must be published and belong to its Campaign'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger campaigns_validate_current_version
before insert or update
on private.campaigns
for each row execute function private.validate_campaign_current_version();

create or replace function private.validate_campaign_version_publication()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_active_fallback_count integer;
begin
  if (
    tg_op = 'INSERT' and new.published_at is not null
  ) or (
    tg_op = 'UPDATE'
    and old.published_at is null
    and new.published_at is not null
  ) then
    select count(*)
    into v_active_fallback_count
    from private.prizes as p
    where p.campaign_version_id = new.id
      and p.is_fallback
      and p.active
      and p.max_quantity is null;

    if v_active_fallback_count <> 1 then
      raise exception 'A published Campaign Version requires exactly one active unlimited fallback Prize'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger campaign_versions_validate_publication
before insert or update
on private.campaign_versions
for each row execute function private.validate_campaign_version_publication();

create or replace function private.protect_published_campaign_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.published_at is not null then
      raise exception 'Published Campaign Versions are immutable';
    end if;
    return old;
  end if;

  if old.published_at is not null then
    raise exception 'Published Campaign Versions are immutable';
  end if;

  return new;
end;
$$;

create trigger campaign_versions_protect_published
before update or delete
on private.campaign_versions
for each row execute function private.protect_published_campaign_version();

create or replace function private.protect_prize_history()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_old_published boolean := false;
  v_new_published boolean := false;
begin
  if tg_op = 'INSERT' then
    select cv.published_at is not null
    into v_new_published
    from private.campaign_versions as cv
    where cv.id = new.campaign_version_id;

    if v_new_published then
      raise exception 'Cannot add Prizes to a published Campaign Version';
    end if;

    return new;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    select cv.published_at is not null
    into v_old_published
    from private.campaign_versions as cv
    where cv.id = old.campaign_version_id;
  end if;

  if tg_op = 'DELETE' then
    if v_old_published then
      raise exception 'Cannot delete Prizes from a published Campaign Version';
    end if;

    return old;
  end if;

  select cv.published_at is not null
  into v_new_published
  from private.campaign_versions as cv
  where cv.id = new.campaign_version_id;

  if v_old_published then
    if (
      to_jsonb(new) - 'issued_quantity' - 'updated_at'
    ) is distinct from (
      to_jsonb(old) - 'issued_quantity' - 'updated_at'
    ) then
      raise exception 'Published Prize configuration is immutable';
    end if;

    if new.issued_quantity < old.issued_quantity then
      raise exception 'Published Prize issued quantity cannot decrease';
    end if;

    return new;
  end if;

  if v_new_published then
    raise exception 'Cannot move a Prize into a published Campaign Version';
  end if;

  return new;
end;
$$;

create trigger prizes_protect_published_history
before insert or update or delete
on private.prizes
for each row execute function private.protect_prize_history();

create or replace function private.prevent_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Audit Logs are append-only';
end;
$$;

create trigger audit_logs_append_only
before update or delete
on private.audit_logs
for each row execute function private.prevent_audit_mutation();

alter table private.branches enable row level security;
alter table private.staff_profiles enable row level security;
alter table private.campaigns enable row level security;
alter table private.campaign_versions enable row level security;
alter table private.prizes enable row level security;
alter table private.gift_entries enable row level security;
alter table private.rewards enable row level security;
alter table private.audit_logs enable row level security;

revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

alter default privileges in schema private
  revoke all on tables from public, anon, authenticated;
alter default privileges in schema private
  revoke all on sequences from public, anon, authenticated;
alter default privileges in schema private
  revoke execute on functions from public, anon, authenticated;
alter default privileges in schema api
  revoke execute on functions from public, anon, authenticated;

create or replace function private.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.staff_profiles as sp
    where sp.id = (select auth.uid())
      and sp.active
  );
$$;

create or replace function private.is_active_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.staff_profiles as sp
    where sp.id = (select auth.uid())
      and sp.active
      and sp.role = 'ADMIN'
  );
$$;

comment on function private.is_active_staff() is
  'For future policies/functions: true only for a signed-in, active Staff or Admin profile.';
comment on function private.is_active_admin() is
  'For future policies/functions: true only for a signed-in, active Admin profile.';

grant usage on schema private to authenticated;
grant execute on function private.is_active_staff() to authenticated;
grant execute on function private.is_active_admin() to authenticated;

-- No table policies or API functions are intentionally created in Phase 1B.
-- With RLS enabled and grants revoked, browser roles have no table access.
