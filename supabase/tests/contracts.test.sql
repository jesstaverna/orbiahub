-- Contratos. Roda depois de rules + tenant + ratelimit + roles + catalog
-- (A: a1 admin, a2 comercial, a3 financeiro, a4 designer; B: b1 admin, b2 comercial). Proposta aceita de A: 'Gestão de redes sociais' (6 meses, desconto 500).
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

-- ===== permissões e modelos-base =====
do $$ begin
  assert (select 'contracts.approve' = any (permissions) and 'contracts.templates' = any (permissions) from roles where key = 'gestor' limit 1), 'Head aprova e gerencia modelos';
  assert (select 'contracts.write' = any (permissions) and not 'contracts.approve' = any (permissions) from roles where key = 'comercial' limit 1), 'comercial escreve, não aprova';
  assert (select 'contracts.read' = any (permissions) and not 'contracts.write' = any (permissions) from roles where key = 'financeiro' limit 1), 'financeiro só lê';
  assert (select count(*) from contract_templates where agency_id = (select id from agencies where slug = 'agencia-a')) = 8, 'A recebeu 8 modelos-base';
  assert (select count(*) from contract_templates where agency_id = (select id from agencies where slug = 'agencia-b')) = 8, 'B recebeu 8 modelos-base';
  assert (select count(*) from clause_library where is_starter and agency_id = (select id from agencies where slug = 'agencia-a')) = 20, 'biblioteca com 20 cláusulas-base (14 gerais + 6 por serviço)';
  assert (select count(*) from contract_template_clauses tc join contract_templates t on t.id = tc.template_id where t.name = 'Social Media (recorrente)' and t.agency_id = (select id from agencies where slug = 'agencia-a')) = 15, 'modelo social media = 15 cláusulas';
  assert (select count(*) from contract_template_clauses tc join contract_templates t on t.id = tc.template_id where t.name = 'Prestação de serviços (geral)' and t.agency_id = (select id from agencies where slug = 'agencia-a')) = 14, 'modelo geral = 14 cláusulas (sem a específica)';
  assert (select description from contract_templates where name = 'Consultoria' limit 1) like '%revisão jurídica obrigatória%', 'modelos avisam que exigem revisão jurídica';
end $$;

create temp table ct as select (select id from proposals where title = 'Gestão de redes sociais') prop_a,
  (select id from proposals where title = 'Proposta do catálogo') prop_draft,
  (select id from contract_templates where name = 'Social Media (recorrente)' and agency_id = (select id from agencies where slug = 'agencia-a')) tpl_a,
  (select id from contract_templates where name = 'Social Media (recorrente)' and agency_id = (select id from agencies where slug = 'agencia-b')) tpl_b;
grant all on ct to authenticated;

-- ===== geração a partir de proposta aceita =====
set role authenticated; select pg_temp.as_user('a2');
create temp table k as select public.contract_generate((select tpl_a from ct), (select prop_a from ct), null, date '2027-01-10') id;
grant all on k to authenticated;
do $$ declare c contracts; body text; begin
  select * into c from contracts where id = (select id from k);
  assert c.status = 'rascunho' and c.number = 1 and c.contract_type = 'recorrente', 'rascunho nº 1 recorrente';
  assert c.monthly_value = 2000 and c.one_time_value = 1000 and c.total_value = 13000, 'valores da proposta (pontual já com desconto): ' || c.one_time_value;
  assert c.start_date = date '2027-01-10' and c.end_date = date '2027-07-09', 'vigência de 6 meses: ' || c.end_date;
  assert jsonb_array_length(c.content) = 15, '15 seções';
  body := c.content::text;
  assert body like '%Padaria Pão Bom%' and body like '%Agência A Ltda%', 'cliente e agência preenchidos';
  assert body like '%R$ 2.000,00%' and body like '%R$ 13.000,00%', 'valores em formato brasileiro';
  assert body like '%Gestão de redes (12 posts/mês)%', 'lista de serviços da proposta';
  assert body like '%10/01/2027%' and body like '%09/07/2027%', 'datas em formato brasileiro';
  assert body like '%[CAMPO A PREENCHER%', 'lacunas ficam sinalizadas (nada é inventado)';
  assert body not like '%{{%', 'todas as variáveis conhecidas foram resolvidas';
  assert c.reviewed_by is null and not c.review_confirmed and c.signed_at is null, 'nasce sem revisão nem assinatura';
  assert (select count(*) from contract_versions where contract_id = c.id) = 1 and exists (select 1 from contract_events where contract_id = c.id and kind = 'criado'), 'versão 1 e evento de criação';
end $$;
-- uma proposta gera um contrato ativo; rascunho de proposta e outras agências não geram
select pg_temp.expect_error($$select public.contract_generate((select tpl_a from ct), (select prop_a from ct))$$, '23505');
select pg_temp.expect_error($$select public.contract_generate((select tpl_a from ct), (select prop_draft from ct))$$, '23514');
select pg_temp.expect_error($$select public.contract_generate((select tpl_a from ct))$$, '22023');
reset role;
set role authenticated; select pg_temp.as_user('b1');
select pg_temp.expect_error($$select public.contract_generate((select tpl_b from ct), (select prop_a from ct))$$);   -- proposta de A é invisível
select pg_temp.expect_error($$select public.contract_generate((select tpl_a from ct), null, (select id from clients limit 1))$$, '23514');   -- modelo de A é invisível
do $$ begin assert (select count(*) from contracts) = 0 and (select count(*) from contract_versions) = 0 and (select count(*) from contract_events) = 0, 'B não vê contratos de A'; end $$;
reset role;

-- ===== ciclo de vida: revisão humana obrigatória =====
set role authenticated; select pg_temp.as_user('a2');
select pg_temp.expect_error($$update contracts set status = 'aguardando_assinatura', review_confirmed = true where id = (select id from k)$$, '23514');   -- não pula a revisão
select pg_temp.expect_error($$update contracts set status = 'assinado' where id = (select id from k)$$, '23514');
select pg_temp.expect_error($$update contracts set reviewed_by = auth.uid() where id = (select id from k)$$, '42501');          -- não forja revisão
update contracts set status = 'em_revisao' where id = (select id from k);
select pg_temp.expect_error($$update contracts set status = 'aguardando_assinatura', review_confirmed = true where id = (select id from k)$$, '42501');  -- comercial não aprova
reset role;
do $$ begin assert exists (select 1 from notifications where title like 'Contrato #1 aguarda revisão'), 'aviso de revisão'; end $$;
set role authenticated; select pg_temp.as_user('a1');
select pg_temp.expect_error($$update contracts set status = 'aguardando_assinatura' where id = (select id from k)$$, '23514');                           -- sem confirmar a revisão
select pg_temp.expect_error($$update contracts set status = 'aguardando_assinatura', review_confirmed = true where id = (select id from k)$$, '23514');  -- ainda há [CAMPO A PREENCHER]
update contracts set content = replace(content::text, '[CAMPO A PREENCHER', 'Preenchido')::jsonb where id = (select id from k);
update contracts set content = jsonb_set(content, '{0,body}', to_jsonb((content->0->>'body') || ' {{variavel.inexistente}}')) where id = (select id from k);
select pg_temp.expect_error($$update contracts set status = 'aguardando_assinatura', review_confirmed = true where id = (select id from k)$$, '23514');  -- variável não resolvida
update contracts set content = jsonb_set(content, '{0,body}', to_jsonb(replace(content->0->>'body', ' {{variavel.inexistente}}', ''))) where id = (select id from k);
update contracts set status = 'aguardando_assinatura', review_confirmed = true where id = (select id from k);
do $$ declare c contracts; begin
  select * into c from contracts where id = (select id from k);
  assert c.reviewed_by = '00000000-0000-0000-0000-0000000000a1' and c.reviewed_at is not null and c.review_confirmed, 'quem aprovou e quando ficam registrados';
end $$;
-- conteúdo travado
select pg_temp.expect_error($$update contracts set title = 'Outro título' where id = (select id from k)$$, '23514');
select pg_temp.expect_error($$update contracts set total_value = 1 where id = (select id from k)$$, '23514');
select pg_temp.expect_error($$update contracts set status = 'rascunho' where id = (select id from k)$$, '23514');
-- voltar à revisão invalida a aprovação
update contracts set status = 'em_revisao' where id = (select id from k);
do $$ begin assert not (select review_confirmed from contracts where id = (select id from k)) and (select reviewed_by from contracts where id = (select id from k)) is null, 'voltar à revisão limpa a aprovação'; end $$;
update contracts set title = 'Contrato de social media — ajustado' where id = (select id from k);
update contracts set status = 'aguardando_assinatura', review_confirmed = true where id = (select id from k);
reset role;

-- ===== assinatura: só registro manual, com evidência; nunca presumida =====
set role authenticated; select pg_temp.as_user('a2');
select pg_temp.expect_error($$update contracts set status = 'assinado', signature_note = 'assinado por e-mail' where id = (select id from k)$$, '42501');   -- comercial não registra assinatura
reset role;
set role authenticated; select pg_temp.as_user('a1');
select pg_temp.expect_error($$update contracts set status = 'assinado' where id = (select id from k)$$, '23514');                                         -- sem evidência
select pg_temp.expect_error($$update contracts set status = 'assinado', signature_note = 'ok' where id = (select id from k)$$, '23514');
select pg_temp.expect_error($$update contracts set status = 'assinado', signature_note = 'Assinado em PDF por ambas as partes, e-mails de 12/01', signature_method = 'provider' where id = (select id from k)$$, '42501');   -- usuário não se passa por provedor
do $$ declare c contracts; begin
  update contracts set status = 'assinado', signature_note = 'Assinado em PDF por ambas as partes (e-mails de 12/01)' where id = (select id from k);
  select * into c from contracts where id = (select id from k);
  assert c.signature_method = 'manual', 'registro do usuário é sempre "manual" (assinatura FORA do sistema)';
  assert c.signed_at is not null and c.status = 'assinado', 'assinado registrado';
end $$;
select pg_temp.expect_error($$update contracts set content = '[]'::jsonb where id = (select id from k)$$, '23514');
select pg_temp.expect_error($$update contracts set status = 'rascunho' where id = (select id from k)$$, '23514');
select pg_temp.expect_error($$update contracts set signature_method = 'provider' where id = (select id from k)$$, '42501');   -- não forja método
reset role;
do $$ begin
  assert exists (select 1 from jobs where type = 'contract.signed') and exists (select 1 from notifications where title = 'Contrato #1 assinado'), 'job e alerta de assinatura';
  assert (select count(*) from contract_events where contract_id = (select id from k) and kind in ('em_revisao','aguardando_assinatura','assinado')) >= 5, 'histórico completo de eventos';
end $$;

-- ===== renovação (decisão humana, registrada) =====
set role authenticated; select pg_temp.as_user('a2');
do $$ declare d date; begin
  d := public.contract_renew((select id from k), 3);
  assert d = date '2027-10-09', 'vigência prorrogada: ' || d;
  assert exists (select 1 from contract_events where kind = 'renovado'), 'renovação registrada';
  assert (select max(version) from contract_versions where contract_id = (select id from k)) >= 2, 'nova versão na renovação';
end $$;
select pg_temp.expect_error($$select public.contract_renew((select id from k), 0)$$, '22023');
reset role;
set role authenticated; select pg_temp.as_user('a4');
select pg_temp.expect_error($$select public.contract_renew((select id from k), 1)$$, '42501');   -- designer não renova
do $$ begin assert (select count(*) from contracts) = 0 and (select count(*) from clause_library) = 0, 'designer não vê contratos nem modelos'; end $$;
reset role;

-- ===== alertas de vencimento (worker) =====
update contracts set start_date = current_date - 100, end_date = current_date + 10 where id = (select id from k);   -- (dono do banco: manutenção)
set role service_role;
do $$ declare r jsonb; begin
  r := public.run_contract_scans();
  assert (r->>'expiring')::int = 1, 'um contrato vencendo: ' || r::text;
  perform public.run_contract_scans();
  assert (select count(*) from notifications where title like 'Contrato #1 vence em%') = 1, 'alerta deduplicado';
end $$;
reset role;
do $$ begin assert (select agency_id from notifications where title like 'Contrato #1 vence em%') = (select agency_id from contracts where id = (select id from k)), 'alerta na agência do contrato'; end $$;
update contracts set end_date = current_date - 1, start_date = current_date - 200 where id = (select id from k);
set role service_role;
do $$ begin
  assert (public.run_contract_scans()->>'expired')::int = 1, 'vigência vencida detectada';
  assert exists (select 1 from notifications where title like 'Contrato #1 com vigência encerrada' and severity = 'critical'), 'alerta crítico';
end $$;
reset role;

-- ===== cancelamento exige motivo; só rascunho é apagável =====
set role authenticated; select pg_temp.as_user('a2');
create temp table k2 as select public.contract_generate((select tpl_a from ct), null, (select id from clients limit 1), null, 'Contrato avulso') id;
grant all on k2 to authenticated;
do $$ declare c contracts; begin
  select * into c from contracts where id = (select id from k2);
  assert c.number = 2 and c.contract_type = 'pontual' and c.total_value = 0 and c.proposal_id is null, 'sem proposta: nº 2, pontual, valores a preencher';
  assert c.content::text like '%[CAMPO A PREENCHER — descrever serviços%', 'serviços ficam como lacuna';
end $$;
select pg_temp.expect_error($$update contracts set status = 'cancelado' where id = (select id from k2)$$, '23514');
update contracts set status = 'cancelado', cancelled_reason = 'Cliente desistiu' where id = (select id from k2);
reset role;
set role authenticated; select pg_temp.as_user('a2');
do $$ declare n int; begin delete from contracts where id = (select id from k); get diagnostics n = row_count; assert n = 0, 'contrato assinado não é apagável'; end $$;
reset role;

-- ===== modelos e cláusulas: gestão exige permissão própria; contratos existentes não mudam =====
set role authenticated; select pg_temp.as_user('a2');
select pg_temp.expect_error($$insert into clause_library (title, body) values ('Minha cláusula', 'texto')$$, '42501');
reset role;
set role authenticated; select pg_temp.as_user('a3');
do $$ begin assert (select count(*) from contracts) >= 1, 'financeiro lê contratos'; end $$;
do $$ declare n int; begin update contracts set payment_terms = 'x' where id = (select id from k); get diagnostics n = row_count; assert n = 0, 'financeiro não altera contratos'; end $$;
reset role;
create temp table before_text as select content::text t from contracts where id = (select id from k);
set role authenticated; select pg_temp.as_user('a1');
update clause_library set body = 'TEXTO NOVO DA CLÁUSULA' where title = 'Objeto e escopo' and agency_id = (select id from agencies where slug = 'agencia-a');
insert into clause_library (title, category, body) values ('Cláusula própria', 'geral', 'Texto da agência para {{cliente.nome}}');
select pg_temp.expect_error($$insert into clause_library (title, body) values ('CLÁUSULA PRÓPRIA', 'duplicada')$$, '23505');
select pg_temp.expect_error($$delete from clause_library where title = 'Partes e definições'$$, '23503');   -- em uso por modelos
select pg_temp.expect_error($$insert into contract_template_clauses (template_id, clause_id) values ((select tpl_b from ct), (select id from clause_library where title = 'Cláusula própria'))$$);   -- modelo de B invisível
reset role;
do $$ begin assert (select content::text from contracts where id = (select id from k)) = (select t from before_text), 'editar a cláusula NÃO altera contrato existente'; end $$;
set role authenticated; select pg_temp.as_user('b1');
do $$ begin assert (select count(*) from clause_library where title = 'Cláusula própria') = 0 and (select count(*) from clause_library) = 20, 'B não vê cláusulas de A'; end $$;
reset role;
do $$ begin assert exists (select 1 from audit_log where table_name = 'contracts' and action = 'UPDATE'), 'contratos são auditados'; end $$;
