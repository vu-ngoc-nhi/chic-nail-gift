-- Verifies the persistent Development-only Phase 3A concurrency run.

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
    select count(*) = 1
      and count(distinct prize_id) = 1
      and count(distinct reward_code) = 1
    from private.rewards
    where gift_entry_id = 'c5000000-0000-0000-0000-000000000001'
  ),
  'CON01-CON02 Same Gift must have one Prize and one Reward Code'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from private.audit_logs
    where action = 'OPEN_GIFT'
      and entity_id = (
        select id
        from private.rewards
        where gift_entry_id = 'c5000000-0000-0000-0000-000000000001'
      )
  ),
  'CON01-CON02 Same Gift must have one first-open Audit event'
);

select pg_temp.assert_true(
  (
    select issued_quantity = 1
      and issued_quantity <= max_quantity
    from private.prizes
    where id = 'c4000000-0000-0000-0000-000000000011'
  )
  and (
    select count(*) = 1
    from private.rewards
    where prize_id = 'c4000000-0000-0000-0000-000000000011'
  )
  and (
    select count(*) = 1
    from private.rewards
    where prize_id = 'c4000000-0000-0000-0000-000000000012'
  ),
  'CON03 Last limited unit must be issued once and the other Gift must use fallback'
);

select pg_temp.assert_true(
  (
    select count(*) = 4
    from private.rewards
    where prize_id = 'c4000000-0000-0000-0000-000000000022'
  )
  and (
    select issued_quantity = 4 and max_quantity is null
    from private.prizes
    where id = 'c4000000-0000-0000-0000-000000000022'
  )
  and (
    select issued_quantity = 1
    from private.prizes
    where id = 'c4000000-0000-0000-0000-000000000021'
  ),
  'CON04 All exhausted-pool Gifts must use fallback without changing exhausted normal inventory'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from private.rewards
    where gift_entry_id = 'c5000000-0000-0000-0000-000000000031'
  )
  and not exists (
    select 1
    from private.audit_logs
    where bill_code_normalized = 'P3A-CON-FAILURE'
  )
  and (
    select status = 'ELIGIBLE'
    from private.gift_entries
    where id = 'c5000000-0000-0000-0000-000000000031'
  ),
  'CON05 Failed assignment must leave no partial Reward, Audit, or Gift transition'
);

select pg_temp.assert_true(
  (
    select count(*) = 7
      and bool_and(status = 'OPENED')
    from private.gift_entries
    where id in (
      'c5000000-0000-0000-0000-000000000001',
      'c5000000-0000-0000-0000-000000000011',
      'c5000000-0000-0000-0000-000000000012',
      'c5000000-0000-0000-0000-000000000021',
      'c5000000-0000-0000-0000-000000000022',
      'c5000000-0000-0000-0000-000000000023',
      'c5000000-0000-0000-0000-000000000024'
    )
  ),
  'CON01-CON04 Every successful Gift must transition exactly once to OPENED'
);

rollback;
