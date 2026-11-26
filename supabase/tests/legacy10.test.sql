-- Dados legados depois da 0010: modelos-base na agência padrão; nada é gerado nem inventado; contrato em branco funciona.
\set ON_ERROR_STOP on
do $$ begin
  assert (select count(*) from contract_templates) = 8 and (select count(*) from clause_library) = 20, 'agência padrão recebeu 8 modelos e 20 cláusulas';
  assert (select count(*) from contracts) = 0, 'nenhum contrato é criado automaticamente';
  assert (select 'contracts.approve' = any (permissions) from roles where key = 'admin'), 'admin aprova contratos';
end $$;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
do $$ declare v_id uuid; begin
  v_id := public.contract_generate((select id from contract_templates where name = 'Consultoria'), null, (select id from clients limit 1), null, 'Contrato legado');
  assert (select number from contracts where contracts.id = v_id) = 1 and (select status from contracts where contracts.id = v_id) = 'rascunho', 'contrato em branco gerado';
end $$;
reset role;
