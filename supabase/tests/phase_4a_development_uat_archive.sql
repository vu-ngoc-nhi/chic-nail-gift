-- DEVELOPMENT ONLY: archive the Phase 4A UAT Campaign after validation.
-- Immutable Campaign Version, Prize, Gift, Reward, and Audit history is retained.

begin;

update private.campaigns
set status = 'ARCHIVED',
    updated_at = statement_timestamp()
where id = 'e2000000-0000-0000-0000-000000000004'
  and name = 'DEVELOPMENT ONLY — Phase 4A Redemption UAT'
  and status in ('ACTIVE', 'PAUSED', 'ENDED');

do $$
begin
  if not exists (
    select 1
    from private.campaigns
    where id = 'e2000000-0000-0000-0000-000000000004'
      and status = 'ARCHIVED'
  ) then
    raise exception 'Phase 4A Development Campaign was not archived';
  end if;
end;
$$;

commit;
