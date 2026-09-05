-- DEVELOPMENT/THROWAWAY ONLY.
-- Persists minimal fixtures so two remote sessions can call create_gift concurrently.
-- Always run phase_1d_concurrency_cleanup.sql after validation.

begin;

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
values (
  '00000000-0000-0000-0000-000000000000',
  '91000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'phase1d-concurrency@example.invalid',
  '',
  now(),
  '{}',
  '{}',
  now(),
  now()
);

insert into private.staff_profiles (id, branch_id, name, role, active)
values (
  '91000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'Phase 1D Concurrency Staff',
  'STAFF',
  true
);

insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
values (
  '92000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001',
  'Phase 1D Concurrency Campaign',
  'DRAFT',
  statement_timestamp() - interval '1 day',
  statement_timestamp() + interval '1 day',
  '91000000-0000-0000-0000-000000000001'
);

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  gift_open_deadline_hours, headline, description, terms, created_by
)
values (
  '93000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  1,
  200000,
  24,
  'Concurrency test',
  'Development-only concurrency fixture.',
  'Test only.',
  '91000000-0000-0000-0000-000000000001'
);

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, expiry_days,
  weight, max_quantity, is_fallback
)
values (
  '94000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001',
  'Concurrency fallback',
  'FREE_SERVICE',
  'Development-only fallback.',
  30000,
  7000,
  30,
  1,
  null,
  true
);

update private.campaign_versions
set published_at = statement_timestamp()
where id = '93000000-0000-0000-0000-000000000001';

update private.campaigns
set current_version_id = '93000000-0000-0000-0000-000000000001',
    status = 'ACTIVE'
where id = '92000000-0000-0000-0000-000000000001';

commit;
