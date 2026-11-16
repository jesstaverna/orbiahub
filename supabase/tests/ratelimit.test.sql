-- Link público: IP real do visitante e limites. Roda depois de rules.test.sql + tenant.test.sql (Agência A com comercial a2).
\set ON_ERROR_STOP on
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
insert into proposals (title, client_display_name) values ('Proposta limite', 'Cliente RL');
update proposals set status = 'enviada' where title = 'Proposta limite';
reset role;
create temp table rl as select token from proposals where title = 'Proposta limite';
grant all on rl to anon;

set role anon;
set request.headers = '{"x-client-ip":"203.0.113.9","x-forwarded-for":"10.0.0.1"}';
do $$ declare t text := (select token from rl); r jsonb; begin
  r := public.proposal_public_open(t);
  assert r->>'title' = 'Proposta limite', 'abre normalmente';
  -- 130 aberturas: o limite é 120 por token / 10 min; acima dele continua legível, mas não conta visualização
  for i in 1..130 loop r := public.proposal_public_open(t); end loop;
  assert r->>'title' = 'Proposta limite', 'acima do limite ainda mostra a proposta (só leitura)';
end $$;
reset role;
do $$ begin
  assert (select view_count from proposals where title = 'Proposta limite') = 120, 'visualizações limitadas a 120: ' || (select view_count from proposals where title = 'Proposta limite');
  assert (select ip from proposal_events e join proposals p on p.id = e.proposal_id where p.title = 'Proposta limite' and e.kind = 'visualizada' limit 1) = '203.0.113.9', 'IP real (x-client-ip) preferido ao x-forwarded-for';
end $$;

-- pedido de alteração: 10 por 10 min por token; o 11º é barrado (P0429)
set role anon;
set request.headers = '{"x-client-ip":"198.51.100.7"}';
do $$ declare t text := (select token from rl); begin
  for i in 1..10 loop assert public.proposal_public_request_changes(t, 'Fulano', 'Pedido ' || i) = true, 'pedido ' || i; end loop;
  begin perform public.proposal_public_request_changes(t, 'Fulano', 'Pedido 11'); assert false, 'deveria limitar'; exception when sqlstate 'P0429' then null; end;
  assert public.proposal_public_accept(t, 'Fulano', 'f@x.com') = true, 'aceite tem bucket próprio (não herda o limite de alteração)';
end $$;
reset role;
do $$ begin
  assert (select count(*) from proposal_events e join proposals p on p.id = e.proposal_id where p.title = 'Proposta limite' and e.kind = 'alteracao_solicitada') = 10, 'só 10 pedidos gravados';
  assert not exists (select 1 from public_rate_limits where bucket like '%' || (select token from rl) || '%'), 'bucket não guarda o token em claro (md5)';
end $$;
-- anon não lê a tabela de limites
set role anon;
do $$ begin begin perform * from public_rate_limits; assert false; exception when insufficient_privilege then null; end; end $$;
reset role;
