-- Development-only seed. This is not customer, campaign, prize, or credential data.
insert into private.branches (id, code, name)
values (
  '00000000-0000-0000-0000-000000000001',
  'CHIC-DEV',
  'Chic Nail & Beauty — Development'
)
on conflict (code) do nothing;
