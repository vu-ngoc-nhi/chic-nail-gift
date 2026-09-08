-- DEVELOPMENT-ONLY Phase 3A hosted concurrency fixtures.
-- Use only in the isolated Supabase Development project, then run the archive script.

begin;

insert into private.branches (id, code, name)
values (
  'c1000000-0000-0000-0000-000000000001',
  'PHASE-3A-CONCURRENCY',
  'Phase 3A Concurrency Test Branch'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  'c1100000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'phase3a-concurrency@example.invalid', '', now(),
  '{}', '{}', now(), now()
);

insert into private.staff_profiles (id, branch_id, name, role, active)
values (
  'c1100000-0000-0000-0000-000000000001',
  'c1000000-0000-0000-0000-000000000001',
  'Phase 3A Concurrency Fixture',
  'ADMIN',
  true
);

insert into private.campaigns (
  id, branch_id, name, status, start_at, end_at, created_by
)
values
  (
    'c2000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000001',
    'Phase 3A Same Gift Concurrency',
    'DRAFT', statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '1 day',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c2000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000001',
    'Phase 3A Last Unit Concurrency',
    'DRAFT', statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '1 day',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c2000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000001',
    'Phase 3A Fallback Concurrency',
    'DRAFT', statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '1 day',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c2000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000001',
    'Phase 3A Failure Atomicity',
    'DRAFT', statement_timestamp() - interval '1 day',
    statement_timestamp() + interval '1 day',
    'c1100000-0000-0000-0000-000000000001'
  );

insert into private.campaign_versions (
  id, campaign_id, version_number, min_bill_vnd,
  gift_open_deadline_hours, headline, description, terms, created_by
)
values
  (
    'c3000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001',
    1, 0, 24, 'Same Gift test', 'Development-only.', 'Test only.',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c3000000-0000-0000-0000-000000000002',
    'c2000000-0000-0000-0000-000000000002',
    1, 0, 24, 'Last Unit test', 'Development-only.', 'Test only.',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c3000000-0000-0000-0000-000000000003',
    'c2000000-0000-0000-0000-000000000003',
    1, 0, 24, 'Fallback test', 'Development-only.', 'Test only.',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c3000000-0000-0000-0000-000000000004',
    'c2000000-0000-0000-0000-000000000004',
    1, 0, 24, 'Failure test', 'Development-only.', 'Test only.',
    'c1100000-0000-0000-0000-000000000001'
  );

insert into private.prizes (
  id, campaign_version_id, name, type, customer_description,
  customer_value_vnd, estimated_chic_cost_vnd, expiry_days,
  weight, max_quantity, issued_quantity, is_fallback, active
)
values
  (
    'c4000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    'Concurrency normal', 'FREE_SERVICE', 'Same Gift normal Prize.',
    10000, 1000, 7, 1, null, 0, false, true
  ),
  (
    'c4000000-0000-0000-0000-000000000002',
    'c3000000-0000-0000-0000-000000000001',
    'Concurrency fallback', 'CUSTOM_REWARD', 'Same Gift fallback.',
    5000, 500, 7, 1, null, 0, true, true
  ),
  (
    'c4000000-0000-0000-0000-000000000011',
    'c3000000-0000-0000-0000-000000000002',
    'Last limited unit', 'FREE_SERVICE', 'Only one concurrent caller may receive this.',
    20000, 2000, 7, 1, 1, 0, false, true
  ),
  (
    'c4000000-0000-0000-0000-000000000012',
    'c3000000-0000-0000-0000-000000000002',
    'Last unit fallback', 'CUSTOM_REWARD', 'Serves the other caller.',
    5000, 500, 7, 1, null, 0, true, true
  ),
  (
    'c4000000-0000-0000-0000-000000000021',
    'c3000000-0000-0000-0000-000000000003',
    'Exhausted normal', 'FREE_SERVICE', 'Already exhausted before test.',
    20000, 2000, 7, 1, 1, 1, false, true
  ),
  (
    'c4000000-0000-0000-0000-000000000022',
    'c3000000-0000-0000-0000-000000000003',
    'Concurrency exhaustion fallback', 'CUSTOM_REWARD', 'Unlimited fallback.',
    5000, 500, 7, 1, null, 0, true, true
  );

update private.campaign_versions
set published_at = statement_timestamp()
where id in (
  'c3000000-0000-0000-0000-000000000001',
  'c3000000-0000-0000-0000-000000000002',
  'c3000000-0000-0000-0000-000000000003'
);

update private.campaigns
set current_version_id = case id
      when 'c2000000-0000-0000-0000-000000000001'::uuid
        then 'c3000000-0000-0000-0000-000000000001'::uuid
      when 'c2000000-0000-0000-0000-000000000002'::uuid
        then 'c3000000-0000-0000-0000-000000000002'::uuid
      when 'c2000000-0000-0000-0000-000000000003'::uuid
        then 'c3000000-0000-0000-0000-000000000003'::uuid
    end,
    status = case id
      when 'c2000000-0000-0000-0000-000000000001'::uuid
        then 'ACTIVE'::private.campaign_status
      else 'ENDED'::private.campaign_status
    end
where id in (
  'c2000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000002',
  'c2000000-0000-0000-0000-000000000003'
);

insert into private.gift_entries (
  id, branch_id, bill_code_entered, bill_amount_vnd,
  campaign_version_id, gift_token, status, open_expires_at, created_by
)
values
  (
    'c5000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-SAME', 1,
    'c3000000-0000-0000-0000-000000000001',
    '13e22b37481c7e5d445b77414be5fc08e8aadcc97e0c493f9e395caae0e69797',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000011',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-LAST-A', 1,
    'c3000000-0000-0000-0000-000000000002',
    '4ac5f1cb11cc7f6bbe2b11c15adbecc3c0956c7732830782fe939a9ebb8a0065',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000012',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-LAST-B', 1,
    'c3000000-0000-0000-0000-000000000002',
    'c20caec5d3068188d5307a7e91fbfe1efca7fade8d9d494d77f4406356451285',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000021',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-FALLBACK-A', 1,
    'c3000000-0000-0000-0000-000000000003',
    'c9bb51e70b9899d2e1d75a5cf4d4f3aff13f4deb61c6505c15b866e8b5de4390',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000022',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-FALLBACK-B', 1,
    'c3000000-0000-0000-0000-000000000003',
    'fc31356f46182f24b4219e800b813fa2697495e9f5e7ac32b5c06bb45055aa9f',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000023',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-FALLBACK-C', 1,
    'c3000000-0000-0000-0000-000000000003',
    '67caefac2c52a531eb6db9ab5cacf7882fd58b902b3ab7d6d0cea2a0618a3b82',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000024',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-FALLBACK-D', 1,
    'c3000000-0000-0000-0000-000000000003',
    'c7fc972cdbf995bc4fc65db65bc5775dac0ca4a3acd4a488191d6ba5090c3534',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  ),
  (
    'c5000000-0000-0000-0000-000000000031',
    'c1000000-0000-0000-0000-000000000001',
    'P3A-CON-FAILURE', 1,
    'c3000000-0000-0000-0000-000000000004',
    '89655fbe22a8d913a2c92ce4a4e3613e3e9d0f283c3b53282fb57ef4c8394515',
    'ELIGIBLE', statement_timestamp() + interval '1 hour',
    'c1100000-0000-0000-0000-000000000001'
  );

commit;
