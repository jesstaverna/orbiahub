-- Isolamento multi-tenant: roda DEPOIS de rules.test.sql (Agência A já tem lead, cliente, proposta ativada, financeiro...).
\set ON_ERROR_STOP on
create or replace function pg_temp.expect_error(sql text, code text default null) returns void language plpgsql as $$
begin
  execute sql;
  raise exception 'ESPERAVA ERRO e nada ocorreu: %', sql;
exception when others then
  if sqlerrm like 'ESPERAVA ERRO%' then raise; end if;
  if code is not null and sqlstate <> code then raise exception 'Erro % diferente de %: % (sql: %)', sqlstate, code, sqlerrm, sql; end if;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b1', 'dono-b@orbiahub.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'comercial-b@orbiahub.test'),
  ('00000000-0000-0000-0000-0000000000c1', 'dono-c@orbiahub.test'),
  ('00000000-0000-0000-0000-0000000000c2', 'c2@orbiahub.test'),
  ('00000000-0000-0000-0000-0000000000c3', 'c3@orbiahub.test'),
  ('00000000-0000-0000-0000-0000000000c4', 'c4@orbiahub.test');
do $$ begin
  assert (select count(*) from profiles where agency_id is null and not is_platform_admin) = 6, 'novos usuários entram sem agência';
  assert (select count(*) from profiles where is_platform_admin) = 1, 'só o primeiro usuário é admin da plataforma';
end $$;

-- ids da Agência A, acessíveis às sessões de teste
create temp table ids as select
  (select id from leads limit 1) lead_a, (select id from clients limit 1) client_a, (select id from proposals limit 1) prop_a,
  (select token from proposals limit 1) token_a, (select id from fin_transactions limit 1) tx_a,
  (select id from agencies where slug = 'agencia-a') agency_a;
grant all on ids to authenticated, anon;

-- ===== só o admin da plataforma cria agências =====
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
select pg_temp.expect_error($$select public.platform_create_agency('X', 'x', 'dono-b@orbiahub.test')$$, '42501');
select pg_temp.expect_error($$select public.platform_set_agency((select agency_a from ids), 'scale', null)$$, '42501');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.expect_error($$select public.platform_create_agency('Y', 'Slug Inválido!', 'dono-b@orbiahub.test')$$, '23514');
select pg_temp.expect_error($$select public.platform_create_agency('Y', 'y', 'naoexiste@orbiahub.test')$$, '23514');
select public.platform_create_agency('Agência B', 'agencia-b', 'dono-b@orbiahub.test', 'pro');
select public.platform_create_agency('Agência C', 'agencia-c', 'dono-c@orbiahub.test', 'trial');
do $$ begin
  assert (select count(*) from agencies) = 3, 'admin da plataforma enxerga todas as agências (metadados)';
  assert (select count(*) from clients) = 1 and (select count(*) from leads) = 1, 'mas só os dados de negócio da sua própria agência (A)';
end $$;
select pg_temp.expect_error($$update agencies set plan = 'scale' where slug = 'agencia-a'$$, '42501');   -- plano/status só via função de plataforma
update agencies set name = 'Agência A Ltda' where slug = 'agencia-a';
select public.platform_set_agency((select id from agencies where slug = 'agencia-a'), 'pro', 'active');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
do $$ declare n int; begin
  update agencies set name = 'invadido' where slug = 'agencia-a'; get diagnostics n = row_count;
  assert n = 0, 'só admin da agência renomeia';
end $$;
select pg_temp.expect_error($$update plans set max_users = 9999$$, '42501');
reset role;

-- ===== Agência B enxerga somente o que é dela =====
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
select public.agency_add_member('comercial-b@orbiahub.test', 'comercial');
do $$ begin
  assert (select count(*) from agencies) = 1 and (select name from agencies) = 'Agência B';
  assert (select count(*) from profiles) = 2, 'B vê só os próprios usuários';
  assert (select count(*) from pipeline_stages) = 9 and (select count(*) from fin_categories) = 10, 'funil e categorias próprios (sementes por agência)';
  assert (select count(*) from clients) + (select count(*) from leads) + (select count(*) from proposals) + (select count(*) from proposal_items)
       + (select count(*) from fin_transactions) + (select count(*) from client_services) + (select count(*) from lead_interactions)
       + (select count(*) from proposal_events) + (select count(*) from goals) = 0, 'nenhum dado de A visível para B';
  assert (select count(*) from audit_log where agency_id is distinct from (select agency_id from profiles where id = auth.uid())) = 0, 'auditoria isolada';
  assert (select count(*) from notifications where agency_id is distinct from (select agency_id from profiles where id = auth.uid())) = 0, 'alertas isolados';
end $$;
-- acesso direto por ID, edição e exclusão cross-tenant não afetam nada
do $$ declare n int; begin
  assert (select count(*) from leads where id = (select lead_a from ids)) = 0;
  assert (select count(*) from proposals where token = (select token_a from ids)) = 0, 'token de proposta de A não é legível por B';
  update leads set name = 'hack' where id = (select lead_a from ids); get diagnostics n = row_count; assert n = 0, 'update cross-tenant';
  delete from clients where id = (select client_a from ids); get diagnostics n = row_count; assert n = 0, 'delete cross-tenant';
  update fin_transactions set status = 'cancelado' where id = (select tx_a from ids); get diagnostics n = row_count; assert n = 0, 'financeiro cross-tenant';
  update profiles set role = 'cliente' where id = '00000000-0000-0000-0000-0000000000a2'; get diagnostics n = row_count; assert n = 0, 'perfil de outra agência';
end $$;
-- forjar agency_id, referenciar registros de A e anexar filhos a pais de A
select pg_temp.expect_error($$insert into clients (agency_id, name) values ((select agency_a from ids), 'forjado')$$, '42501');
select pg_temp.expect_error($$insert into leads (name, email, stage_id, client_id) select 'X', 'x@x.com', id, (select client_a from ids) from pipeline_stages limit 1$$, '42501');
select pg_temp.expect_error($$insert into proposal_items (proposal_id, description, unit_price) values ((select prop_a from ids), 'x', 1)$$, '42501');
select pg_temp.expect_error($$insert into lead_interactions (lead_id, kind, content) values ((select lead_a from ids), 'nota', 'x')$$, '42501');
select pg_temp.expect_error($$insert into fin_transactions (direction, description, amount, due_date, client_id) values ('in', 'x', 1, current_date, (select client_a from ids))$$, '42501');
-- vínculo de agência / perfil de plataforma são imutáveis pelo usuário
select pg_temp.expect_error($$update profiles set agency_id = (select agency_a from ids) where id = auth.uid()$$, '42501');
select pg_temp.expect_error($$update profiles set is_platform_admin = true where id = auth.uid()$$, '42501');
-- funções definer respeitam a agência
select pg_temp.expect_error($$select public.activate_proposal((select prop_a from ids), current_date)$$);
select pg_temp.expect_error($$select public.platform_create_agency('Z', 'z', 'c2@orbiahub.test')$$, '42501');
do $$ begin assert public.agency_add_member('comercial@orbiahub.test', 'admin') = false, 'não rouba usuário de outra agência'; end $$;
reset role;
do $$ begin assert (select agency_id from profiles where email = 'comercial@orbiahub.test') = (select agency_a from ids) and (select role from profiles where email = 'comercial@orbiahub.test') = 'comercial'; end $$;

set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';   -- comercial de B não administra membros
select pg_temp.expect_error($$select public.agency_add_member('c2@orbiahub.test', 'comercial')$$, '42501');
reset role;

-- ===== dados próprios de B convivem com os de A (mesmo e-mail, mesma numeração) =====
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
insert into leads (name, email, stage_id) select 'Maria Silva', 'maria@paobom.com', id from pipeline_stages where name = 'Novo Lead';   -- mesmo e-mail do lead de A: permitido
select pg_temp.expect_error($$insert into leads (name, email, stage_id) select 'Outra', 'MARIA@paobom.com', id from pipeline_stages where name = 'Novo Lead'$$, '23505');  -- duplicado dentro de B: barrado
insert into proposals (title, lead_id, client_display_name) select 'Proposta B', id, 'Maria' from leads;
insert into fin_transactions (direction, description, amount, due_date, category_id)
  select 'in', 'Cobrança B vencida', 700, current_date - 5, id from fin_categories where name = 'Serviços pontuais';
do $$ begin assert (select number from proposals) = 1, 'numeração de propostas é por agência'; end $$;
reset role;
do $$ begin
  assert (select count(*) from proposals where number = 1) = 2, 'A e B têm a proposta nº 1';
  assert (select count(*) from jobs where type = 'lead.created' and agency_id = (select id from agencies where slug = 'agencia-b')) = 1, 'job do lead de B carrega a agência de B';
end $$;

-- varredura do worker notifica cada agência no seu escopo
set role service_role;
select public.run_scheduled_scans();
reset role;
do $$ declare b uuid := (select id from agencies where slug = 'agencia-b'); a uuid := (select agency_a from ids); begin
  assert exists (select 1 from notifications n join fin_transactions t on n.dedupe_key = 'overdue:' || t.id where t.agency_id = b and n.agency_id = b), 'alerta de atraso de B na agência B';
  assert exists (select 1 from notifications n join fin_transactions t on n.dedupe_key = 'overdue:' || t.id where t.agency_id = a and n.agency_id = a), 'alerta de atraso de A na agência A';
  assert not exists (select 1 from notifications n join fin_transactions t on n.dedupe_key = 'overdue:' || t.id where t.agency_id <> n.agency_id), 'nenhum alerta vaza para outra agência';
  assert (select count(*) from fin_transactions where recurring_id is not null and agency_id <> (select agency_id from fin_recurring where id = recurring_id)) = 0;
end $$;

-- link público: continua funcionando por token, agora com a identidade da agência
set role anon;
do $$ declare r jsonb; begin
  r := public.proposal_public_open((select token_a from ids));
  assert r->'agency'->>'name' = 'Agência A Ltda', 'proposta pública traz a agência dona';
  assert not (r ? 'agency_id'), 'não expõe ids internos';
end $$;
reset role;

-- ===== limites de plano (Agência C = trial: 3 usuários, 10 clientes) =====
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
select public.agency_add_member('c2@orbiahub.test', 'comercial');
select public.agency_add_member('c3@orbiahub.test', 'designer');
select pg_temp.expect_error($$select public.agency_add_member('c4@orbiahub.test', 'designer')$$, '53400');
do $$ begin
  for i in 1..10 loop insert into clients (name) values ('Cliente ' || i); end loop;
  begin insert into clients (name) values ('Cliente 11'); assert false, 'deveria barrar o 11º cliente'; exception when sqlstate '53400' then null; end;
end $$;
reset role;

-- ===== suspensão: agência suspensa perde acesso imediatamente =====
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select public.platform_set_agency((select id from agencies where slug = 'agencia-b'), null, 'suspended');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
do $$ begin
  assert app.current_agency_id() is null and app.user_role() is null, 'agência suspensa: sem contexto';
  assert (select count(*) from leads) = 0 and (select count(*) from agencies) = 0, 'agência suspensa não lê nada';
end $$;
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select public.platform_set_agency((select id from agencies where slug = 'agencia-b'), null, 'active');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';
do $$ begin assert (select count(*) from leads) = 1, 'reativada: volta a enxergar os próprios dados'; end $$;
reset role;

-- ===== anon continua sem acesso a nada =====
set role anon;
select pg_temp.expect_error($$select * from agencies$$, '42501');
select pg_temp.expect_error($$select * from plans$$, '42501');
select pg_temp.expect_error($$select * from agency_counters$$, '42501');
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.expect_error($$select * from agency_counters$$, '42501');
reset role;
