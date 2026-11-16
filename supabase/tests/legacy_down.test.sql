-- Depois do ROLLBACK sobre dados existentes: nada perdido, comportamento single-tenant restaurado.
\set ON_ERROR_STOP on
do $$ begin
  assert to_regclass('public.agencies') is null and to_regclass('public.plans') is null, 'tabelas de tenant removidas';
  assert not exists (select 1 from information_schema.columns where table_schema = 'public' and column_name = 'agency_id'), 'colunas agency_id removidas';
  assert (select count(*) from clients) = 1 and (select count(*) from leads) = 1 and (select count(*) from proposals) = 3 and (select count(*) from proposal_items) = 1, 'dados preservados';
  assert (select count(*) from fin_transactions) = 1 and (select count(*) from goals) = 1 and (select count(*) from profiles) = 2, 'financeiro, metas e usuários preservados';
  assert (select count(*) from pipeline_stages) = 9 and (select count(*) from fin_categories) = 10, 'funil e categorias preservados';
  assert nextval('public.proposal_number_seq') = 4, 'sequência de propostas retomada após o maior número';
end $$;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';
do $$ begin assert (select count(*) from leads) = 1, 'RLS single-tenant original funciona'; end $$;
reset role;
