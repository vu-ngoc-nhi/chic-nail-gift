-- DEVELOPMENT/THROWAWAY ONLY.
-- Removes only deterministic Phase 1D concurrency fixtures.
-- Trigger changes and cleanup are atomic: failure rolls everything back.

begin;

alter table private.audit_logs disable trigger audit_logs_append_only;
delete from private.audit_logs
where actor_id = '91000000-0000-0000-0000-000000000001';
alter table private.audit_logs enable trigger audit_logs_append_only;

delete from private.rewards
where gift_entry_id in (
  select ge.id
  from private.gift_entries as ge
  where ge.created_by = '91000000-0000-0000-0000-000000000001'
);

delete from private.gift_entries
where created_by = '91000000-0000-0000-0000-000000000001';

update private.campaigns
set status = 'DRAFT',
    current_version_id = null
where id = '92000000-0000-0000-0000-000000000001';

alter table private.prizes disable trigger prizes_protect_published_history;
delete from private.prizes
where campaign_version_id = '93000000-0000-0000-0000-000000000001';
alter table private.prizes enable trigger prizes_protect_published_history;

alter table private.campaign_versions
  disable trigger campaign_versions_protect_published;
delete from private.campaign_versions
where id = '93000000-0000-0000-0000-000000000001';
alter table private.campaign_versions
  enable trigger campaign_versions_protect_published;

delete from private.campaigns
where id = '92000000-0000-0000-0000-000000000001';

delete from private.staff_profiles
where id = '91000000-0000-0000-0000-000000000001';

delete from auth.users
where id = '91000000-0000-0000-0000-000000000001';

commit;
