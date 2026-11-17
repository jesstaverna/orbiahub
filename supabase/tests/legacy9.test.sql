-- Dados legados depois da 0009: papéis de sistema ganham as permissões do catálogo; nada mais muda.
\set ON_ERROR_STOP on
do $$ begin
  assert (select 'catalog.manage' = any (permissions) from roles where key = 'admin'), 'admin da agência padrão gerencia o catálogo';
  assert (select 'catalog.read' = any (permissions) and not 'catalog.manage' = any (permissions) from roles where key = 'comercial'), 'comercial só lê';
  assert (select count(*) from service_catalog) = 0, 'nenhum serviço/preço é inventado';
  assert (select count(*) from proposal_items) = 1 and (select service_id from proposal_items) is null, 'itens antigos intactos';
end $$;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
insert into service_catalog (name, billing, unit_price) values ('Serviço legado', 'mensal', 100);
do $$ begin assert (select count(*) from service_catalog) = 1; end $$;
reset role;
