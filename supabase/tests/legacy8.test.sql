-- Dados legados depois de 0006+0007+0008: papéis semeados na agência padrão e permissões equivalentes às de antes.
\set ON_ERROR_STOP on
do $$ begin
  assert (select count(*) from roles) = 7, 'agência padrão recebeu os 7 papéis';
  assert (select count(*) from profiles where agency_id is not null) = 2 and not exists (select 1 from profiles p where agency_id is not null and not exists (select 1 from roles r where r.agency_id = p.agency_id and r.key = p.role)), 'todo usuário aponta para um papel existente';
end $$;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d2';
do $$ begin assert (select count(*) from leads) = 1 and (select count(*) from fin_transactions) = 0, 'comercial legado mantém exatamente o acesso de antes'; end $$;
reset role;
set role authenticated; set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d1';
do $$ begin assert (select count(*) from fin_transactions) = 1 and (select count(*) from audit_log) > 0, 'admin legado mantém acesso total'; end $$;
reset role;
