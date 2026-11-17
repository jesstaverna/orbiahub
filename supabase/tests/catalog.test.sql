-- Catálogo de serviços e pacotes. Roda depois de rules + tenant + ratelimit + roles
-- (A: a1 admin, a2 comercial, a3 financeiro, a4 designer; B: b1 admin, b2 comercial).
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

-- ===== permissões padrão =====
do $$ begin
  assert (select 'catalog.manage' = any (permissions) from roles where key = 'admin' limit 1), 'admin gerencia o catálogo';
  assert (select 'catalog.manage' = any (permissions) and 'catalog.read' = any (permissions) from roles where key = 'gestor' limit 1), 'Head gerencia o catálogo';
  assert (select 'catalog.read' = any (permissions) and not 'catalog.manage' = any (permissions) from roles where key = 'comercial' limit 1), 'comercial só lê';
  assert (select not 'catalog.read' = any (permissions) from roles where key = 'designer' limit 1), 'designer não vê catálogo';
end $$;

-- ===== administrador monta o catálogo =====
set role authenticated; select pg_temp.as_user('a1');
insert into service_catalog (name, category, billing, unit_price, description, deliverables)
  values ('Gestão de redes sociais', 'social_media', 'mensal', 2000, 'Planejamento e publicação', array['12 posts/mês', '4 stories/mês']);
insert into service_catalog (name, category, billing, unit_price) values ('Setup de identidade de conteúdo', 'social_media', 'pontual', 1500);
insert into service_catalog (name, category, billing, unit_price) values ('Serviço avulso', 'outro', 'pontual', 300);
select pg_temp.expect_error($$insert into service_catalog (name) values ('GESTÃO DE REDES SOCIAIS')$$, '23505');   -- nome único por agência (sem diferenciar maiúsculas)... acentos iguais
select pg_temp.expect_error($$insert into service_catalog (name, unit_price) values ('Preço negativo', -1)$$, '23514');
select pg_temp.expect_error($$insert into service_catalog (name, category) values ('Categoria inválida', 'xyz')$$, '23514');
insert into packages (name, description) values ('Social Starter', 'Setup + gestão mensal');
insert into package_items (package_id, service_id, quantity, position)
  select p.id, s.id, 1, 0 from packages p, service_catalog s where p.name = 'Social Starter' and s.name = 'Gestão de redes sociais';
insert into package_items (package_id, service_id, quantity, unit_price_override, position)
  select p.id, s.id, 1, 1000, 1 from packages p, service_catalog s where p.name = 'Social Starter' and s.name = 'Setup de identidade de conteúdo';
do $$ begin
  begin insert into package_items (package_id, service_id) select p.id, s.id from packages p, service_catalog s where p.name = 'Social Starter' and s.name = 'Gestão de redes sociais'; assert false, 'duplicado no pacote';
  exception when unique_violation then null; end;
  assert (select count(*) from package_items) = 2;
  assert (select count(*) from package_items where agency_id = (select agency_id from packages where name = 'Social Starter')) = 2, 'itens herdam a agência do pacote';
end $$;
reset role;

-- ===== quem lê não escreve; quem não tem a permissão não vê =====
set role authenticated; select pg_temp.as_user('a2');
do $$ begin assert (select count(*) from service_catalog) = 3 and (select count(*) from packages) = 1, 'comercial lê o catálogo'; end $$;
select pg_temp.expect_error($$insert into service_catalog (name) values ('Comercial não cria')$$, '42501');
do $$ declare n int; begin update service_catalog set unit_price = 1; get diagnostics n = row_count; assert n = 0, 'comercial não altera preços'; end $$;
reset role;
set role authenticated; select pg_temp.as_user('a4');
do $$ begin assert (select count(*) from service_catalog) = 0 and (select count(*) from packages) = 0, 'designer não vê o catálogo'; end $$;
reset role;

-- ===== isolamento entre agências =====
set role authenticated; select pg_temp.as_user('b1');
do $$ begin assert (select count(*) from service_catalog) = 0 and (select count(*) from packages) = 0 and (select count(*) from package_items) = 0, 'B não vê o catálogo de A'; end $$;
insert into service_catalog (name, unit_price) values ('Gestão de redes sociais', 999);   -- mesmo nome em outra agência: permitido
insert into packages (name) values ('Pacote B');
reset role;
create temp table cat as select (select id from service_catalog where agency_id = (select id from agencies where slug = 'agencia-a') and name = 'Setup de identidade de conteúdo') svc_a,
                                (select id from packages where name = 'Pacote B') pkg_b;
grant all on cat to authenticated;
set role authenticated; select pg_temp.as_user('b1');
select pg_temp.expect_error($$insert into package_items (package_id, service_id) values ((select pkg_b from cat), (select svc_a from cat))$$, '42501');   -- referência a serviço de A
reset role;

-- ===== incluir no proposta: cópia dos dados =====
set role authenticated; select pg_temp.as_user('a2');
insert into proposals (title, client_display_name) values ('Proposta do catálogo', 'Cliente Catálogo');
create temp table pp as select id from proposals where title = 'Proposta do catálogo';
grant all on pp to authenticated;
do $$ declare n int; begin
  n := public.proposal_add_from_catalog((select id from pp), (select id from service_catalog where name = 'Gestão de redes sociais'), null, 2);
  assert n = 1, 'um serviço incluído';
  assert (select quantity from proposal_items where description = 'Gestão de redes sociais') = 2, 'quantidade informada';
  assert (select unit_price from proposal_items where description = 'Gestão de redes sociais') = 2000, 'preço copiado do catálogo';
  assert (select details from proposal_items where description = 'Gestão de redes sociais') like '%Entregáveis: 12 posts/mês; 4 stories/mês%', 'entregáveis nos detalhes';
  assert (select service_id from proposal_items where description = 'Gestão de redes sociais') is not null, 'origem registrada';
  n := public.proposal_add_from_catalog((select id from pp), null, (select id from packages where name = 'Social Starter'));
  assert n = 2, 'pacote expande em 2 itens';
  assert (select unit_price from proposal_items where description = 'Setup de identidade de conteúdo') = 1000, 'preço do pacote (override) vence o do catálogo';
  assert (select count(distinct position) from proposal_items) = 3, 'posições sequenciais e sem colisão';
  assert (select subtotal_one_time from proposals where title = 'Proposta do catálogo') = 1000, 'totais da proposta recalculados (pontual)';
  assert (select subtotal_monthly from proposals where title = 'Proposta do catálogo') = 2 * 2000 + 2000, 'totais da proposta recalculados (mensal)';
end $$;
select pg_temp.expect_error($$select public.proposal_add_from_catalog((select id from pp))$$, '22023');                     -- nem serviço nem pacote
select pg_temp.expect_error($$select public.proposal_add_from_catalog((select id from pp), (select id from service_catalog limit 1), (select id from packages limit 1))$$, '22023');  -- ambos
select pg_temp.expect_error($$select public.proposal_add_from_catalog((select id from pp), gen_random_uuid())$$, '23514');   -- serviço inexistente
reset role;

-- mudar o catálogo NÃO altera proposta existente
set role authenticated; select pg_temp.as_user('a1');
update service_catalog set unit_price = 5000 where name = 'Gestão de redes sociais';
reset role;
do $$ begin assert (select unit_price from proposal_items where description = 'Gestão de redes sociais' limit 1) = 2000, 'proposta mantém o preço copiado'; end $$;

-- inativos não entram; excluir serviço usado por proposta preserva o item
set role authenticated; select pg_temp.as_user('a1');
update service_catalog set active = false where name = 'Setup de identidade de conteúdo';
select pg_temp.expect_error($$select public.proposal_add_from_catalog((select id from pp), (select id from service_catalog where name = 'Setup de identidade de conteúdo'))$$, '23514');
update service_catalog set active = true where name = 'Setup de identidade de conteúdo';
reset role;
set role authenticated; select pg_temp.as_user('a2');
select public.proposal_add_from_catalog((select id from pp), (select id from service_catalog where name = 'Serviço avulso'));
reset role;
set role authenticated; select pg_temp.as_user('a1');
select pg_temp.expect_error($$delete from service_catalog where name = 'Gestão de redes sociais'$$, '23503');   -- está em pacote: desative em vez de apagar
delete from service_catalog where name = 'Serviço avulso';
reset role;
do $$ begin assert (select service_id from proposal_items where description = 'Serviço avulso') is null and exists (select 1 from proposal_items where description = 'Serviço avulso'), 'item da proposta sobrevive à exclusão do serviço'; end $$;

-- quem não tem permissão de catálogo (designer) ou é de outra agência não consegue incluir
set role authenticated; select pg_temp.as_user('b1');
select pg_temp.expect_error($$select public.proposal_add_from_catalog((select id from pp), (select id from service_catalog limit 1))$$);   -- proposta de A é invisível para B
reset role;
set role authenticated; select pg_temp.as_user('a4');
select pg_temp.expect_error($$select public.proposal_add_from_catalog((select id from pp), gen_random_uuid())$$);
reset role;
do $$ begin assert exists (select 1 from audit_log where table_name = 'service_catalog' and action = 'INSERT'), 'catálogo é auditado'; end $$;
