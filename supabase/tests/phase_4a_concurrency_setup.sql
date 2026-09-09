-- ISOLATED TEST DATABASE ONLY: persistent fixture for true multi-session redemption.

begin;

insert into private.branches (id, code, name)
values ('f1000000-0000-0000-0000-000000000004', 'PHASE-4A-CONCURRENCY', 'Phase 4A Concurrency Test');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000000',
    'f1100000-0000-0000-0000-000000000041',
    'authenticated', 'authenticated', 'phase4a-concurrency-a@example.invalid', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'f1100000-0000-0000-0000-000000000042',
    'authenticated', 'authenticated', 'phase4a-concurrency-b@example.invalid', '', now(),
    '{}', '{}', now(), now()
  );

insert into private.staff_profiles (id, branch_id, name, role, active)
values
  (
    'f1100000-0000-0000-0000-000000000041',
    'f1000000-0000-0000-0000-000000000004',
    'Phase 4A Concurrent Staff A', 'STAFF', true
  ),
  (
    'f1100000-0000-0000-0000-000000000042',
    'f1000000-0000-0000-0000-000000000004',
    'Phase 4A Concurrent Staff B', 'STAFF', true
  );

insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
values (
  'f2000000-0000-0000-0000-000000000004',
  'f1000000-0000-0000-0000-000000000004',
  'Phase 4A Concurrency Campaign', 'DRAFT', now() - interval '1 day', now() + interval '1 day',
  'f1100000-0000-0000-0000-000000000041'
);

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd, headline, description, terms, created_by
)
values (
  'f3000000-0000-0000-0000-000000000004',
  'f2000000-0000-0000-0000-000000000004',
  1, 0, 'Concurrency test', 'Isolated test only.', 'Test only.',
  'f1100000-0000-0000-0000-000000000041'
);

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, minimum_spend_vnd,
  expiry_days, weight, max_quantity, issued_quantity, is_fallback, active
)
values (
  'f4000000-0000-0000-0000-000000000004',
  'f3000000-0000-0000-0000-000000000004',
  'Concurrency Prize', 'CUSTOM_REWARD', 'Concurrency test Reward.',
  10000, 1000, 300000, 30, 1, null, 1, true, true
);

update private.campaign_versions
set published_at = statement_timestamp()
where id = 'f3000000-0000-0000-0000-000000000004';

update private.campaigns
set current_version_id = 'f3000000-0000-0000-0000-000000000004',
    status = 'ENDED'
where id = 'f2000000-0000-0000-0000-000000000004';

insert into private.gift_entries (
  id, branch_id, bill_code_entered, bill_amount_vnd, campaign_version_id,
  gift_token, status, created_by, opened_at
)
values (
  'f5000000-0000-0000-0000-000000000004',
  'f1000000-0000-0000-0000-000000000004',
  'P4A-CONCURRENCY-SOURCE', 400000,
  'f3000000-0000-0000-0000-000000000004',
  encode(extensions.gen_random_bytes(32), 'hex'),
  'OPENED', 'f1100000-0000-0000-0000-000000000041', statement_timestamp()
);

insert into private.rewards (
  id, gift_entry_id, prize_id, reward_code, prize_snapshot, expires_at
)
values (
  'f6000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000004',
  'f4000000-0000-0000-0000-000000000004',
  'CHIC-RD4CON',
  '{"name":"Concurrency Prize","type":"CUSTOM_REWARD","customer_description":"Concurrency test Reward.","customer_value_vnd":10000,"discount_percent":null,"minimum_spend_vnd":300000,"applicable_service":null,"campaign_terms":"Test only.","expiry_days":30}',
  statement_timestamp() + interval '30 days'
);

commit;
