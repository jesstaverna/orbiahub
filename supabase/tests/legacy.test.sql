-- Depois da 0006 sobre dados existentes: tudo atribuído à "Agência padrão", sem perda nem duplicação.
\set ON_ERROR_STOP on
do $$ declare a uuid; begin
  assert (select count(*) from agencies) = 1, 'uma agência criada';
  select id into a from agencies;
  assert (select slug from agencies) = 'agencia-padrao' and (select plan from agencies) = 'internal';
  assert (select count(*) from profiles where agency_id = a) = 2, 'usuários migrados';
  assert (select is_platform_admin from profiles where email = 'legado-admin@orbiahub.test'), 'operador vira admin da plataforma';
  assert (select count(*) from clients where agency_id = a) = 1 and (select count(*) from leads where agency_id = a) = 1, 'clientes e leads';
  assert (select count(*) from proposals where agency_id = a) = 2 and (select count(*) from proposal_items where agency_id = a) = 1, 'propostas e itens';
  assert (select count(*) from fin_transactions where agency_id = a) = 1 and (select count(*) from goals where agency_id = a) = 1, 'financeiro e metas';
  assert (select count(*) from pipeline_stages) = 9 and (select count(*) from fin_categories) = 10, 'sementes não duplicadas';
  assert not exists (select 1 from audit_log where agency_id is null and table_name in ('clients','leads','proposals')), 'auditoria antiga atribuída à agência';
  assert not exists (select 1 from jobs where type = 'lead.created' and agency_id is null), 'jobs antigos atribuídos';
  assert (select value from agency_counters where key = 'proposal') = 2, 'contador de propostas continua do maior número';
end $$;

-- usuários legados enxergam seus dados via RLS normalmente
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';
do $$ begin assert (select count(*) from leads) = 1 and (select count(*) from fin_transactions) = 0, 'comercial legado: leads sim, financeiro não'; end $$;
insert into proposals (title, client_display_name) values ('Proposta Legada 3', 'Novo');
do $$ begin assert (select number from proposals where title = 'Proposta Legada 3') = 3, 'numeração segue de onde parou'; end $$;
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
do $$ begin assert (select count(*) from proposals) = 3 and (select count(*) from clients) = 1, 'admin legado vê tudo da agência'; end $$;
reset role;
