-- Papéis e permissões configuráveis. Roda depois de rules + tenant + ratelimit (Agência A: a1 admin, a2 comercial, a3 financeiro, a4 designer; B: b1 admin, b2 comercial).
\set ON_ERROR_STOP on
create or replace function pg_temp.expect_error(sql text, code text default null) returns void language plpgsql as $$
begin
  execute sql;
  raise exception 'ESPERAVA ERRO e nada ocorreu: %', sql;
exception when others then
  if sqlerrm like 'ESPERAVA ERRO%' then raise; end if;
  if code is not null and sqlstate <> code then raise exception 'Erro % diferente de %: % (sql: %)', sqlstate, code, sqlerrm, sql; end if;
end $$;
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || u, false); end $$;

-- ===== sementes: 7 papéis de sistema por agência, incluindo Gestor/Head =====
do $$ begin
  assert (select count(*) from roles where agency_id = (select id from agencies where slug = 'agencia-a')) = 7, 'agência A tem 7 papéis';
  assert (select count(*) from roles where agency_id = (select id from agencies where slug = 'agencia-b')) = 7, 'agência B tem 7 papéis';
  assert exists (select 1 from roles where key = 'gestor' and name = 'Gestor / Head' and is_system), 'Gestor/Head existe';
  assert (select permissions = app.all_permissions() from roles where key = 'admin' limit 1), 'admin tem todas as permissões';
  assert (select permissions = '{}' from roles where key = 'cliente' limit 1), 'cliente não tem permissões';
  assert not app.can('app.access'), 'sem login não há permissão';
end $$;

-- ===== administrador cria e edita papéis =====
set role authenticated; select pg_temp.as_user('a1');
insert into roles (key, name, permissions) values ('estagio', 'Estagiário', array['app.access', 'clients.read']);
insert into roles (key, name, permissions, is_system) values ('forjado', 'Forjado', array['app.access'], true);
do $$ begin assert not (select is_system from roles where key = 'forjado'), 'usuário não consegue criar papel de sistema'; end $$;
select pg_temp.expect_error($$insert into roles (key, name, permissions) values ('invalido', 'X', array['app.access', 'inventada.permissao'])$$, '23514');
select pg_temp.expect_error($$insert into roles (key, name) values ('Ab', 'Chave inválida')$$, '23514');
-- admin e cliente são fixos; papéis de sistema não são apagados nem mudam de chave
select pg_temp.expect_error($$update roles set permissions = '{}' where key = 'admin'$$, '42501');
select pg_temp.expect_error($$delete from roles where key = 'admin'$$, '42501');
select pg_temp.expect_error($$update roles set name = 'Outro' where key = 'cliente'$$, '42501');
select pg_temp.expect_error($$delete from roles where key = 'gestor'$$, '42501');
select pg_temp.expect_error($$update roles set key = 'novachave' where key = 'estagio'$$, '42501');
update roles set permissions = permissions || array['crm.access'] where key = 'designer';          -- papel de sistema editável
do $$ begin assert (select 'crm.access' = any (permissions) from roles where key = 'designer'), 'papel de sistema editável'; end $$;
update roles set permissions = array['app.access', 'clients.read', 'brand.access'] where key = 'designer';  -- volta ao padrão
select pg_temp.expect_error($$select public.agency_add_member('x@x.com', 'inexistente')$$, '22023');
select pg_temp.expect_error($$select public.agency_add_member('x@x.com', 'cliente')$$, '22023');
reset role;

-- ===== quem não gerencia não escreve papéis; B não enxerga nem usa papéis de A =====
set role authenticated; select pg_temp.as_user('a2');
do $$ begin assert (select count(*) from roles) >= 7, 'equipe lê os papéis da agência'; end $$;
select pg_temp.expect_error($$insert into roles (key, name) values ('meupapel', 'Meu papel')$$, '42501');
do $$ declare n int; begin update roles set permissions = array['app.access'] where key = 'financeiro'; get diagnostics n = row_count; assert n = 0, 'comercial não edita papéis'; end $$;
reset role;
set role authenticated; select pg_temp.as_user('b1');
do $$ declare n int; begin
  assert (select count(*) from roles) = 7 and not exists (select 1 from roles where key = 'estagio'), 'B vê só os papéis de B';
  update roles set permissions = array['app.access'] where key = 'comercial'; get diagnostics n = row_count; assert n = 1, 'B edita o próprio papel';
  update roles set permissions = array['app.access','clients.read'] where key = 'comercial' and agency_id = (select id from agencies where slug = 'agencia-a'); get diagnostics n = row_count; assert n = 0, 'B não edita papel de A';
end $$;
select pg_temp.expect_error($$update profiles set role = 'estagio' where email = 'comercial-b@orbiahub.test'$$, '23503');   -- papel de A não existe em B
update roles set permissions = array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','goals.read','brand.access','reports.access','ai.access'] where key = 'comercial';  -- restaura B
reset role;

-- ===== atribuir papel customizado: efeito imediato, sem tocar em código =====
set role authenticated; select pg_temp.as_user('a1');
update profiles set role = 'estagio' where email = 'designer@orbiahub.test';
reset role;
set role authenticated; select pg_temp.as_user('a4');
do $$ begin
  assert (select count(*) from clients) >= 1, 'estagiário lê clientes';
  assert (select count(*) from leads) = 0, 'mas não vê leads';
end $$;
select pg_temp.expect_error($$insert into clients (name) values ('Cliente do estagiário')$$, '42501');
reset role;
set role authenticated; select pg_temp.as_user('a1');
update roles set permissions = permissions || array['crm.access'] where key = 'estagio';
reset role;
set role authenticated; select pg_temp.as_user('a4');
do $$ begin assert (select count(*) from leads) >= 1, 'permissão adicionada vale imediatamente'; end $$;
reset role;
set role authenticated; select pg_temp.as_user('a1');
select pg_temp.expect_error($$delete from roles where key = 'estagio'$$, '23503');   -- em uso
update profiles set role = 'designer' where email = 'designer@orbiahub.test';
delete from roles where key = 'estagio';
do $$ begin assert not exists (select 1 from roles where key = 'estagio'), 'papel sem uso pode ser apagado'; end $$;
reset role;

-- ===== Gestor/Head: permissões de comercial + tráfego; sem financeiro, auditoria nem desconto =====
set role authenticated; select pg_temp.as_user('a1');
update profiles set role = 'gestor' where email = 'comercial@orbiahub.test';
reset role;
set role authenticated; select pg_temp.as_user('a2');
do $$ begin
  assert (select count(*) from leads) >= 1 and (select count(*) from proposals) >= 1, 'Head vê CRM e propostas';
  assert (select count(*) from fin_transactions) = 0 and (select count(*) from audit_log) = 0, 'Head não vê financeiro nem auditoria';
end $$;
select pg_temp.expect_error($$update proposals set discount_value = 100 where title = 'Proposta limite'$$, '42501');   -- sem permissão de desconto
reset role;
set role authenticated; select pg_temp.as_user('a1');
update roles set permissions = permissions || array['proposals.discount'] where key = 'gestor';   -- agência decide: Head pode dar desconto
reset role;
set role authenticated; select pg_temp.as_user('a2');
select pg_temp.expect_error($$update proposals set discount_value = 100 where title = 'Proposta limite'$$, '23514');   -- passou na permissão; barrado pela regra de valor
reset role;
set role authenticated; select pg_temp.as_user('a1');
update roles set permissions = array_remove(permissions, 'proposals.discount') where key = 'gestor';
update profiles set role = 'comercial' where email = 'comercial@orbiahub.test';
reset role;

-- gerir usuários é uma permissão, não um papel: Head com settings.manage edita perfis; sem ela, não
set role authenticated; select pg_temp.as_user('a1');
update profiles set role = 'gestor' where email = 'comercial@orbiahub.test';
reset role;
set role authenticated; select pg_temp.as_user('a2');
do $$ declare n int; begin update profiles set role = 'designer' where email = 'financeiro@orbiahub.test'; get diagnostics n = row_count; assert n = 0, 'sem settings.manage não edita perfis'; end $$;
select pg_temp.expect_error($$update profiles set role = 'admin' where id = auth.uid()$$, '42501');   -- nem a si mesmo
reset role;
set role authenticated; select pg_temp.as_user('a1');
update roles set permissions = permissions || array['settings.manage'] where key = 'gestor';
reset role;
set role authenticated; select pg_temp.as_user('a2');
do $$ declare n int; begin update profiles set role = 'financeiro' where email = 'financeiro@orbiahub.test'; get diagnostics n = row_count; assert n = 1, 'com settings.manage edita perfis'; end $$;
reset role;
set role authenticated; select pg_temp.as_user('a1');
update roles set permissions = array_remove(permissions, 'settings.manage') where key = 'gestor';
update profiles set role = 'comercial' where email = 'comercial@orbiahub.test';
reset role;
do $$ begin assert (select role from profiles where email = 'comercial@orbiahub.test') = 'comercial' and (select role from profiles where email = 'financeiro@orbiahub.test') = 'financeiro'; end $$;
