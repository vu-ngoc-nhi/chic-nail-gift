-- ISOLATED TEST DATABASE ONLY: retain history but deactivate the concurrency fixture.

begin;

update private.campaigns
set status = 'ARCHIVED', updated_at = statement_timestamp()
where id = 'f2000000-0000-0000-0000-000000000004';

update private.staff_profiles
set active = false, updated_at = statement_timestamp()
where id in (
  'f1100000-0000-0000-0000-000000000041',
  'f1100000-0000-0000-0000-000000000042'
);

update private.branches
set active = false
where id = 'f1000000-0000-0000-0000-000000000004';

commit;
