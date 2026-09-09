-- DEVELOPMENT ONLY: verify Phase 4A real UAT after UI and concurrency checks.
-- Expected fake source Bills: P4A-UAT-UI-001 and P4A-UAT-CON-001.

begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(p_condition, false) then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;

select pg_temp.assert_true(
  (
    select count(*) = 2
      and count(distinct r.id) = 2
      and bool_and(r.redeemed_at is not null)
      and bool_and(r.redeemed_by = '175a726d-30a2-4348-8505-d177c34f9f29'::uuid)
      and bool_and(r.redemption_bill_code is not null)
      and bool_and(r.redemption_bill_amount_vnd >= 300000)
    from private.gift_entries as ge
    join private.rewards as r on r.gift_entry_id = ge.id
    where ge.bill_code_normalized in ('P4A-UAT-UI-001', 'P4A-UAT-CON-001')
  ),
  'Phase 4A UAT must leave exactly two successfully redeemed Development Rewards'
);

select pg_temp.assert_true(
  (
    select count(*) = 2
    from private.audit_logs as al
    join private.rewards as r on r.id = al.entity_id
    join private.gift_entries as ge on ge.id = r.gift_entry_id
    where al.action = 'REDEEM_GIFT'
      and ge.bill_code_normalized in ('P4A-UAT-UI-001', 'P4A-UAT-CON-001')
  ),
  'Each UAT Reward must have exactly one successful REDEEM_GIFT Audit event'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.audit_logs as al
    join private.rewards as r on r.id = al.entity_id
    join private.gift_entries as ge on ge.id = r.gift_entry_id
    where al.action = 'REDEEM_GIFT'
      and ge.bill_code_normalized = 'P4A-UAT-CON-001'
  ),
  'Concurrent redemption must create exactly one successful Audit event'
);

select pg_temp.assert_true(
  (
    select result_code = 'ALREADY_OPENED'
      and reward_available
      and reward_status = 'REDEEMED'
    from api.open_gift(
      (
        select gift_token
        from private.gift_entries
        where bill_code_normalized = 'P4A-UAT-UI-001'
      )
    )
  ),
  'Customer revisit must return the same REDEEMED Reward'
);

rollback;
