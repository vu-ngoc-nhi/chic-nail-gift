-- DEVELOPMENT ONLY: Phase 4A real UAT Campaign fixture for CHIC-DEV.
-- Run after the Phase 4A migration in the isolated Supabase Development project.

begin;

do $$
begin
  if not exists (
    select 1
    from private.staff_profiles as sp
    join private.branches as b on b.id = sp.branch_id
    where sp.id = '175a726d-30a2-4348-8505-d177c34f9f29'::uuid
      and sp.active
      and sp.role in ('STAFF', 'ADMIN')
      and b.code = 'CHIC-DEV'
      and b.active
  ) then
    raise exception 'Phase 4A UAT requires the approved active Development Staff on CHIC-DEV';
  end if;

  if exists (
    select 1
    from private.campaigns as c
    join private.branches as b on b.id = c.branch_id
    where b.code = 'CHIC-DEV'
      and c.status = 'ACTIVE'
  ) then
    raise exception 'Archive or end the existing CHIC-DEV Campaign before Phase 4A UAT';
  end if;
end;
$$;

-- 1. Create the DRAFT Campaign.
insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
select
  'e2000000-0000-0000-0000-000000000004'::uuid,
  b.id,
  'DEVELOPMENT ONLY — Phase 4A Redemption UAT',
  'DRAFT'::private.campaign_status,
  statement_timestamp() - interval '1 hour',
  statement_timestamp() + interval '7 days',
  '175a726d-30a2-4348-8505-d177c34f9f29'::uuid
from private.branches as b
where b.code = 'CHIC-DEV';

-- 2. Create the unpublished Campaign Version.
insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  gift_open_deadline_hours, headline, description, terms, created_by
)
values (
  'e3000000-0000-0000-0000-000000000004',
  'e2000000-0000-0000-0000-000000000004',
  1,
  200000,
  24,
  'Quà thử nghiệm Phase 4A',
  'Dữ liệu Development phục vụ kiểm thử quy trình sử dụng quà.',
  'Chỉ dùng cho UAT. Mỗi quà sử dụng một lần.',
  '175a726d-30a2-4348-8505-d177c34f9f29'
);

-- 3. Create exactly one active, unlimited fallback Prize.
insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, discount_percent,
  minimum_spend_vnd, applicable_service, expiry_days,
  weight, max_quantity, issued_quantity, is_fallback, active
)
values (
  'e4000000-0000-0000-0000-000000000004',
  'e3000000-0000-0000-0000-000000000004',
  'DEVELOPMENT ONLY — Chăm sóc nail Phase 4A',
  'FREE_SERVICE',
  'Phần quà thử nghiệm quy trình sử dụng quà.',
  100000,
  20000,
  null,
  300000,
  'Dịch vụ nail',
  30,
  1,
  null,
  0,
  true,
  true
);

-- 4. Publish the Campaign Version after its fallback Prize exists.
update private.campaign_versions
set published_at = statement_timestamp()
where id = 'e3000000-0000-0000-0000-000000000004';

-- 5. Assign the published Version.
update private.campaigns
set current_version_id = 'e3000000-0000-0000-0000-000000000004'
where id = 'e2000000-0000-0000-0000-000000000004';

-- 6. Activate the Campaign.
update private.campaigns
set status = 'ACTIVE'
where id = 'e2000000-0000-0000-0000-000000000004';

commit;
