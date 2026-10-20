-- Phase 5A Admin Campaign Builder checks.
-- Run only against an isolated local/development database; all fixtures roll back.

begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if not coalesce(p_condition, false) then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;

create or replace function pg_temp.assert_raises(
  p_statement text,
  p_expected_state text,
  p_message text
)
returns void language plpgsql as $$
declare v_state text;
begin
  begin
    execute p_statement;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if v_state = p_expected_state then return; end if;
    raise exception 'ASSERTION FAILED: % (expected %, received %)', p_message, p_expected_state, v_state;
  end;
  raise exception 'ASSERTION FAILED: % (statement did not fail)', p_message;
end;
$$;

insert into private.branches (id, code, name)
values
  ('e5000000-0000-0000-0000-000000000001', 'PHASE-5A-A', 'Phase 5A Branch A'),
  ('e5000000-0000-0000-0000-000000000002', 'PHASE-5A-B', 'Phase 5A Branch B');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', 'e5100000-0000-0000-0000-000000000001',
   'authenticated', 'authenticated', 'phase5a-admin@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'e5100000-0000-0000-0000-000000000002',
   'authenticated', 'authenticated', 'phase5a-staff@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'e5100000-0000-0000-0000-000000000003',
   'authenticated', 'authenticated', 'phase5a-admin-b@example.invalid', '', now(), '{}', '{}', now(), now());

insert into private.staff_profiles (id, branch_id, name, role, active)
values
  ('e5100000-0000-0000-0000-000000000001', 'e5000000-0000-0000-0000-000000000001', 'Phase 5A Admin', 'ADMIN', true),
  ('e5100000-0000-0000-0000-000000000002', 'e5000000-0000-0000-0000-000000000001', 'Phase 5A Staff', 'STAFF', true),
  ('e5100000-0000-0000-0000-000000000003', 'e5000000-0000-0000-0000-000000000002', 'Phase 5A Admin B', 'ADMIN', true);

-- ADM01: anon cannot use Admin operations.
set local role anon;
select pg_temp.assert_raises(
  'select * from api.list_admin_campaigns()', '42501',
  'ADM01 anon must not execute Admin operations'
);
reset role;

-- ADM02: authenticated STAFF cannot use Admin operations.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000002', true);
select pg_temp.assert_raises(
  'select * from api.list_admin_campaigns()', '42501',
  'ADM02 Staff must not execute Admin operations'
);

-- Use the active branch-A Admin for the remaining API operations.
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);

-- ADM03 and ADM05: active Admin creates a Draft Campaign plus its initial Draft Version.
select
  set_config('chic_gift.phase_5a_campaign_id', result ->> 'campaign_id', true),
  set_config('chic_gift.phase_5a_version_id', result ->> 'campaign_version_id', true)
from (
  select api.create_campaign_draft(
    'Phase 5A Campaign', now() - interval '1 hour', now() + interval '30 days',
    300000, 72, 'Quà bí mật Phase 5A', 'Mô tả an toàn.', 'Điều kiện Phase 5A.'
  ) as result
) as created;
reset role;

select pg_temp.assert_true(
  (select c.status = 'DRAFT'
      and c.branch_id = 'e5000000-0000-0000-0000-000000000001'
      and c.created_by = 'e5100000-0000-0000-0000-000000000001'
   from private.campaigns as c
   where c.id = current_setting('chic_gift.phase_5a_campaign_id')::uuid),
  'ADM03 active Admin must create a branch-scoped Draft Campaign'
);
select pg_temp.assert_true(
  (select cv.published_at is null and cv.version_number = 1
   from private.campaign_versions as cv
   where cv.id = current_setting('chic_gift.phase_5a_version_id')::uuid),
  'ADM05 initial Campaign Version must be an unpublished Version 1'
);

-- ADM04: invalid dates are rejected.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_raises(
  $$select api.create_campaign_draft(
    'Invalid dates', now(), now() - interval '1 day', 0, 24,
    'Invalid', '', ''
  )$$,
  '23514', 'ADM04 invalid Campaign dates must be rejected'
);

-- ADM06: Draft Campaign/Version settings remain editable.
select api.update_campaign_draft(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid,
  current_setting('chic_gift.phase_5a_version_id')::uuid,
  'Phase 5A Campaign Updated', now() - interval '2 hours', now() + interval '31 days',
  350000, 48, 'Tiêu đề đã cập nhật', 'Mô tả đã cập nhật.', 'Điều kiện đã cập nhật.'
);
reset role;
select pg_temp.assert_true(
  (select c.name = 'Phase 5A Campaign Updated' and cv.min_bill_vnd = 350000 and cv.gift_open_deadline_hours = 48
   from private.campaigns as c
   join private.campaign_versions as cv on cv.campaign_id = c.id
   where c.id = current_setting('chic_gift.phase_5a_campaign_id')::uuid
     and cv.id = current_setting('chic_gift.phase_5a_version_id')::uuid),
  'ADM06 Draft settings must be editable'
);

-- ADM07: a valid normal Prize can be created; actor and ownership are server-scoped.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select set_config(
  'chic_gift.phase_5a_normal_prize_id',
  api.save_draft_prize(
    current_setting('chic_gift.phase_5a_campaign_id')::uuid,
    current_setting('chic_gift.phase_5a_version_id')::uuid,
    null, 'Voucher Phase 5A', 'CASH_VOUCHER', 'Tặng voucher 50.000đ.',
    50000, 15000, null, 0, null, 30, 7, 100, false, true
  ) ->> 'prize_id',
  true
);
reset role;
select pg_temp.assert_true(
  (select p.weight = 7 and p.max_quantity = 100 and not p.is_fallback
   from private.prizes as p
   where p.id = current_setting('chic_gift.phase_5a_normal_prize_id')::uuid),
  'ADM07 Admin must create a valid normal Draft Prize'
);

-- A Draft Prize change is allowed and receives its own Audit event.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select api.save_draft_prize(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid,
  current_setting('chic_gift.phase_5a_version_id')::uuid,
  current_setting('chic_gift.phase_5a_normal_prize_id')::uuid,
  'Voucher Phase 5A', 'CASH_VOUCHER', 'Tặng voucher 50.000đ.',
  50000, 15000, null, 0, null, 30, 9, 100, false, true
);
reset role;
select pg_temp.assert_true(
  (select weight = 9 from private.prizes
   where id = current_setting('chic_gift.phase_5a_normal_prize_id')::uuid),
  'ADM07 Draft Prize changes must persist safely'
);

-- ADM08: invalid normal Prize configuration is rejected.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_raises(
  format(
    $$select api.save_draft_prize(%L::uuid, %L::uuid, null, 'Invalid', 'CASH_VOUCHER',
      'Invalid weight.', 0, 0, null, 0, null, 30, 0, null, false, true)$$,
    current_setting('chic_gift.phase_5a_campaign_id'),
    current_setting('chic_gift.phase_5a_version_id')
  ),
  '23514', 'ADM08 normal Prize weight must be positive'
);

-- ADM10: zero fallback prevents publication.
select pg_temp.assert_raises(
  format(
    'select api.publish_campaign_version(%L::uuid, %L::uuid)',
    current_setting('chic_gift.phase_5a_campaign_id'),
    current_setting('chic_gift.phase_5a_version_id')
  ),
  '23514', 'ADM10 publication must require a fallback Prize'
);

-- ADM09: limited fallback is rejected, then a valid active unlimited fallback is accepted.
select pg_temp.assert_raises(
  format(
    $$select api.save_draft_prize(%L::uuid, %L::uuid, null, 'Limited fallback', 'CUSTOM_REWARD',
      'Fallback.', 10000, 5000, null, 0, null, 30, 1, 2, true, true)$$,
    current_setting('chic_gift.phase_5a_campaign_id'),
    current_setting('chic_gift.phase_5a_version_id')
  ),
  '23514', 'ADM09 fallback must use unlimited inventory'
);
select set_config(
  'chic_gift.phase_5a_fallback_prize_id',
  api.save_draft_prize(
    current_setting('chic_gift.phase_5a_campaign_id')::uuid,
    current_setting('chic_gift.phase_5a_version_id')::uuid,
    null, 'Quà dự phòng Phase 5A', 'CUSTOM_REWARD', 'Quà cảm ơn dành cho khách.',
    10000, 5000, null, 0, null, 30, 1, null, true, true
  ) ->> 'prize_id',
  true
);
reset role;
select pg_temp.assert_true(
  (select p.is_fallback and p.active and p.max_quantity is null
   from private.prizes as p
   where p.id = current_setting('chic_gift.phase_5a_fallback_prize_id')::uuid),
  'ADM09 fallback must persist as active and unlimited'
);

-- ADM11: the schema and Admin RPC prevent multiple fallback Prizes.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select pg_temp.assert_raises(
  format(
    $$select api.save_draft_prize(%L::uuid, %L::uuid, null, 'Second fallback', 'CUSTOM_REWARD',
      'Fallback 2.', 0, 0, null, 0, null, 30, 1, null, true, true)$$,
    current_setting('chic_gift.phase_5a_campaign_id'),
    current_setting('chic_gift.phase_5a_version_id')
  ),
  '23505', 'ADM11 multiple fallback Prizes must be rejected'
);

-- ADM12: an existing fallback cannot be changed to limited inventory.
select pg_temp.assert_raises(
  format(
    $$select api.save_draft_prize(%L::uuid, %L::uuid, %L::uuid, 'Fallback', 'CUSTOM_REWARD',
      'Fallback.', 0, 0, null, 0, null, 30, 1, 1, true, true)$$,
    current_setting('chic_gift.phase_5a_campaign_id'),
    current_setting('chic_gift.phase_5a_version_id'),
    current_setting('chic_gift.phase_5a_fallback_prize_id')
  ),
  '23514', 'ADM12 limited fallback update must be rejected'
);

-- ADM13: valid configuration publishes and becomes current without activation.
select api.publish_campaign_version(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid,
  current_setting('chic_gift.phase_5a_version_id')::uuid
);
reset role;
select pg_temp.assert_true(
  (select cv.published_at is not null and c.current_version_id = cv.id and c.status = 'DRAFT'
   from private.campaigns as c
   join private.campaign_versions as cv on cv.campaign_id = c.id
   where c.id = current_setting('chic_gift.phase_5a_campaign_id')::uuid
     and cv.id = current_setting('chic_gift.phase_5a_version_id')::uuid),
  'ADM13 valid Version must publish without auto-activation'
);

-- ADM14-ADM15: published Version and Prize configuration remain immutable.
select pg_temp.assert_raises(
  format('update private.campaign_versions set headline = %L where id = %L::uuid',
    'Unsafe mutation', current_setting('chic_gift.phase_5a_version_id')),
  'P0001', 'ADM14 published Campaign Version must remain immutable'
);
select pg_temp.assert_raises(
  format('update private.prizes set name = %L where id = %L::uuid',
    'Unsafe mutation', current_setting('chic_gift.phase_5a_normal_prize_id')),
  'P0001', 'ADM15 published Prize configuration must remain immutable'
);

-- ADM16: valid published Campaign activates only with explicit confirmation.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select api.set_campaign_lifecycle(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid, 'ACTIVATE', true
);
reset role;
select pg_temp.assert_true(
  (select status = 'ACTIVE' from private.campaigns
   where id = current_setting('chic_gift.phase_5a_campaign_id')::uuid),
  'ADM16 a valid published Campaign must activate'
);

-- Prepare a second fully publishable Campaign for active-conflict and cloning checks.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select
  set_config('chic_gift.phase_5a_campaign_2_id', result ->> 'campaign_id', true),
  set_config('chic_gift.phase_5a_version_2_id', result ->> 'campaign_version_id', true)
from (
  select api.create_campaign_draft(
    'Phase 5A Campaign 2', now() - interval '1 hour', now() + interval '10 days',
    0, 24, 'Campaign 2', 'Mô tả.', 'Điều kiện.'
  ) as result
) as created;
select api.save_draft_prize(
  current_setting('chic_gift.phase_5a_campaign_2_id')::uuid,
  current_setting('chic_gift.phase_5a_version_2_id')::uuid,
  null, 'Normal 2', 'CUSTOM_REWARD', 'Normal 2.', 1, 1, null, 0, null, 7, 1, 10, false, true
);
select api.save_draft_prize(
  current_setting('chic_gift.phase_5a_campaign_2_id')::uuid,
  current_setting('chic_gift.phase_5a_version_2_id')::uuid,
  null, 'Fallback 2', 'CUSTOM_REWARD', 'Fallback 2.', 1, 1, null, 0, null, 7, 1, null, true, true
);
select api.publish_campaign_version(
  current_setting('chic_gift.phase_5a_campaign_2_id')::uuid,
  current_setting('chic_gift.phase_5a_version_2_id')::uuid
);

-- ADM17: another ACTIVE Campaign for the branch is denied without silent replacement.
select pg_temp.assert_raises(
  format('select api.set_campaign_lifecycle(%L::uuid, %L, true)',
    current_setting('chic_gift.phase_5a_campaign_2_id'), 'ACTIVATE'),
  '23514', 'ADM17 second active Campaign must be denied'
);

-- ADM18: pausing prevents new Gift issuance under the existing create_gift rule.
select api.set_campaign_lifecycle(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid, 'PAUSE', false
);
select pg_temp.assert_true(
  (select result_code = 'NO_ACTIVE_CAMPAIGN' from api.create_gift('P5A-PAUSED', 500000)),
  'ADM18 paused Campaign must not issue new Gifts'
);

-- ADM19: resume works while dates/configuration remain valid.
select pg_temp.assert_true(
  (api.set_campaign_lifecycle(
    current_setting('chic_gift.phase_5a_campaign_id')::uuid, 'RESUME', false
  ) ->> 'status') = 'ACTIVE',
  'ADM19 resume must return ACTIVE while dates/configuration remain valid'
);

-- Create one valid Gift before closing the Campaign.
select set_config(
  'chic_gift.phase_5a_gift_token',
  (select gift_token from api.create_gift('P5A-HISTORY', 500000)),
  true
);

-- ADM20: END works and stops issuance without deleting the Campaign.
select api.set_campaign_lifecycle(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid, 'END', true
);
reset role;
select pg_temp.assert_true(
  (select status = 'ENDED' from private.campaigns
   where id = current_setting('chic_gift.phase_5a_campaign_id')::uuid),
  'ADM20 Campaign must enter ENDED state'
);

-- ADM21: ARCHIVE preserves Campaign, Version, Prize, and issued Gift history.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select api.set_campaign_lifecycle(
  current_setting('chic_gift.phase_5a_campaign_id')::uuid, 'ARCHIVE', true
);
reset role;
select pg_temp.assert_true(
  (select c.status = 'ARCHIVED'
      and exists (select 1 from private.campaign_versions as cv where cv.campaign_id = c.id)
      and exists (select 1 from private.gift_entries as ge where ge.campaign_version_id = c.current_version_id)
   from private.campaigns as c
   where c.id = current_setting('chic_gift.phase_5a_campaign_id')::uuid),
  'ADM21 archive must preserve immutable operational history'
);

-- ADM22: an already-issued Gift remains accessible and openable after END/ARCHIVE.
set local role anon;
select pg_temp.assert_true(
  (select valid and may_open from api.get_public_gift(current_setting('chic_gift.phase_5a_gift_token'))),
  'ADM22 archived Campaign must not invalidate an eligible issued Gift'
);
select pg_temp.assert_true(
  (select result_code = 'OPENED_NOW' from api.open_gift(current_setting('chic_gift.phase_5a_gift_token'))),
  'ADM22 issued Gift must still open after Campaign archival'
);

-- ADM23: customer APIs never expose Admin-only estimated Chic cost.
select pg_temp.assert_true(
  (select not (to_jsonb(public_gift) ? 'estimated_chic_cost_vnd')
   from api.get_public_gift(current_setting('chic_gift.phase_5a_gift_token')) as public_gift),
  'ADM23 public Gift payload must not expose internal Chic cost'
);
select pg_temp.assert_true(
  (select not (to_jsonb(opened_gift) ? 'estimated_chic_cost_vnd')
   from api.open_gift(current_setting('chic_gift.phase_5a_gift_token')) as opened_gift),
  'ADM23 open Gift payload must not expose internal Chic cost'
);
reset role;

-- ADM24: created_by/actor identity comes from auth.uid(), not an RPC input.
select pg_temp.assert_true(
  (select c.created_by = 'e5100000-0000-0000-0000-000000000001'
   from private.campaigns as c
   where c.id = current_setting('chic_gift.phase_5a_campaign_id')::uuid),
  'ADM24 server must resolve the authenticated Admin actor'
);

-- ADM25: all meaningful Admin lifecycle/configuration actions are audited append-only.
select pg_temp.assert_true(
  (select count(distinct action) = 11
   from private.audit_logs
   where actor_id = 'e5100000-0000-0000-0000-000000000001'
     and action in (
       'CREATE_CAMPAIGN', 'CREATE_CAMPAIGN_VERSION', 'EDIT_CAMPAIGN',
       'CREATE_PRIZE', 'EDIT_PRIZE', 'PUBLISH_CAMPAIGN', 'ACTIVATE_CAMPAIGN',
       'PAUSE_CAMPAIGN', 'RESUME_CAMPAIGN', 'END_CAMPAIGN',
       'ARCHIVE_CAMPAIGN'
     )),
  'ADM25 required Admin and lifecycle Audit events must be recorded'
);

-- Version cloning: source history stays unchanged and the clone is editable/unpublished.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000001', true);
select
  set_config('chic_gift.phase_5a_clone_id', result ->> 'campaign_version_id', true),
  set_config('chic_gift.phase_5a_clone_number', result ->> 'version_number', true)
from (
  select api.create_new_campaign_version(
    current_setting('chic_gift.phase_5a_campaign_2_id')::uuid
  ) as result
) as cloned;
reset role;
select pg_temp.assert_true(
  (select clone.published_at is null
      and clone.version_number = 2
      and source.published_at is not null
      and (select count(*) from private.prizes where campaign_version_id = clone.id) = 2
      and not exists (
        select 1 from private.prizes where campaign_version_id = clone.id and issued_quantity <> 0
      )
   from private.campaign_versions as clone
   join private.campaign_versions as source
     on source.id = current_setting('chic_gift.phase_5a_version_2_id')::uuid
   where clone.id = current_setting('chic_gift.phase_5a_clone_id')::uuid),
  'Version clone must be editable, unpublished, complete, and reset issued quantities'
);

-- Branch isolation: another branch Admin cannot read branch-A Campaigns.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e5100000-0000-0000-0000-000000000003', true);
select pg_temp.assert_true(
  not exists (
    select 1 from api.list_admin_campaigns()
    where campaign_id = current_setting('chic_gift.phase_5a_campaign_id')::uuid
  ),
  'Admin Campaign list must remain branch-scoped'
);
reset role;

rollback;
