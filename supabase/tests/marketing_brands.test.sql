\set ON_ERROR_STOP on
begin;
-- Run after tenant fixtures (a1/b1 are administrators).
create function pg_temp.brand_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || u, true); end $$;
set local role authenticated;
select pg_temp.brand_user('a1');
insert into public.marketing_brands (name,segment) values ('Brand CI A','Design');
do $$ begin
  assert (select count(*) from public.marketing_brands where name = 'Brand CI A') = 1, 'A can read own brand';
  begin
    insert into public.marketing_brands(name) values (' brand ci a ');
    raise exception 'duplicate accepted';
  exception when unique_violation then null;
  end;
end $$;
update public.marketing_brands set active = false where name = 'Brand CI A';
do $$ begin assert (select not active from public.marketing_brands where name = 'Brand CI A'), 'archive works'; end $$;
reset role;
create temp table brand_fixture as select id,agency_id from public.marketing_brands where name = 'Brand CI A';
grant select on brand_fixture to authenticated;
set local role authenticated;
select pg_temp.brand_user('b1');
do $$ declare n integer; begin
  assert not exists(select 1 from public.marketing_brands where name = 'Brand CI A'), 'B cannot read A';
  update public.marketing_brands set active = true where id = (select id from brand_fixture);
  get diagnostics n = row_count;
  assert n = 0, 'B cannot update A';
  begin
    insert into public.marketing_brands(agency_id,name) values ((select agency_id from brand_fixture),'Forged tenant');
    raise exception 'forged tenant accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
insert into public.marketing_brands(name) values ('Brand CI A');
reset role;
set local role authenticated;
select pg_temp.brand_user('a4');
do $$ begin
  begin
    insert into public.marketing_brands(name) values ('Unauthorized');
    raise exception 'unauthorized insert accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$ begin
  assert exists(select 1 from public.audit_log where table_name='marketing_brands' and action='INSERT'), 'insert audited';
  assert exists(select 1 from public.audit_log where table_name='marketing_brands' and action='UPDATE'), 'update audited';
end $$;
rollback;
