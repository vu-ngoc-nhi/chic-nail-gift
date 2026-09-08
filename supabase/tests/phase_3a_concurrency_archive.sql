-- Archives the Development-only concurrency fixture without bypassing history.

begin;

update private.campaigns
set status = 'ARCHIVED',
    updated_at = statement_timestamp()
where id in (
  'c2000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000002',
  'c2000000-0000-0000-0000-000000000003',
  'c2000000-0000-0000-0000-000000000004'
);

update private.staff_profiles
set active = false,
    updated_at = statement_timestamp()
where id = 'c1100000-0000-0000-0000-000000000001';

update private.branches
set active = false
where id = 'c1000000-0000-0000-0000-000000000001';

commit;
