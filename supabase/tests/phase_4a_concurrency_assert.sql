-- Verifies the result after concurrent calls against phase_4a_concurrency_setup.sql.

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
    select redeemed_at is not null
      and redeemed_by in (
        'f1100000-0000-0000-0000-000000000041'::uuid,
        'f1100000-0000-0000-0000-000000000042'::uuid
      )
      and redemption_bill_code in ('P4A-CON-A', 'P4A-CON-B')
      and redemption_bill_amount_vnd = 300000
    from private.rewards
    where id = 'f6000000-0000-0000-0000-000000000004'
  ),
  'RDC01 One request must establish one complete final redemption'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
      and count(distinct actor_id) = 1
      and count(distinct bill_code_normalized) = 1
    from private.audit_logs
    where action = 'REDEEM_GIFT'
      and entity_id = 'f6000000-0000-0000-0000-000000000004'
  ),
  'RDC01 Concurrent calls must create exactly one successful Audit event'
);

select pg_temp.assert_true(
  (
    select redemption_bill_code not in ('P4A-CON-REPEAT-A', 'P4A-CON-REPEAT-B')
      and redemption_bill_amount_vnd = 300000
    from private.rewards
    where id = 'f6000000-0000-0000-0000-000000000004'
  )
  and (
    select count(*) = 1
    from private.audit_logs
    where action = 'REDEEM_GIFT'
      and entity_id = 'f6000000-0000-0000-0000-000000000004'
  ),
  'RDC02 Repeated concurrent calls must not mutate original redemption metadata'
);

rollback;
