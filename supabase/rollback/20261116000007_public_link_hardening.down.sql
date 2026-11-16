-- ORBIAHUB — rollback da 0007 (endurecimento do link público). GERADO a partir das definições da 0003 e da 0006, sem edição.

create or replace function app.client_ip() returns text language sql stable as $$
  select nullif(split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1), '')
$$;

create or replace function public.proposal_public_open(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.proposals; v_items jsonb; v_agency jsonb;
begin
  select * into p from public.proposals where token = p_token and status <> 'rascunho';
  if not found then return null; end if;

  if p.valid_until is not null and p.valid_until < app.br_date(now()) and p.status in ('enviada','visualizada','em_negociacao') then
    update public.proposals set status = 'expirada' where id = p.id returning * into p;
  end if;

  if p.status in ('enviada','visualizada','em_negociacao') or p.status = 'aceita' or p.status = 'expirada' or p.status = 'recusada' then
    update public.proposals
       set view_count = view_count + 1,
           first_viewed_at = coalesce(first_viewed_at, now()),
           status = case when status = 'enviada' then 'visualizada' else status end
     where id = p.id returning * into p;
    insert into public.proposal_events (proposal_id, kind, ip) values (p.id, 'visualizada', app.client_ip());
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('description', description, 'details', details, 'billing', billing,
                                               'quantity', quantity, 'unit_price', unit_price, 'line_total', line_total) order by position), '[]'::jsonb)
    into v_items from public.proposal_items where proposal_id = p.id;
  select jsonb_build_object('name', a.name, 'brand', a.brand) into v_agency from public.agencies a where a.id = p.agency_id;

  return jsonb_build_object(
    'number', p.number, 'title', p.title, 'status', p.status, 'client_name', p.client_display_name,
    'content', p.content, 'payment_terms', p.payment_terms, 'installments', p.installments,
    'contract_months', p.contract_months, 'valid_until', p.valid_until, 'discount_value', p.discount_value,
    'subtotal_one_time', p.subtotal_one_time, 'subtotal_monthly', p.subtotal_monthly, 'total_value', p.total_value,
    'accepted_at', p.accepted_at, 'accepted_by_name', p.accepted_by_name, 'items', v_items, 'agency', v_agency);
end $$;

create or replace function public.proposal_public_accept(p_token text, p_name text, p_email text) returns boolean
language plpgsql security definer set search_path = public as $$
declare p public.proposals;
begin
  if coalesce(btrim(p_name), '') = '' or coalesce(btrim(p_email), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Informe nome e e-mail válidos para registrar o aceite' using errcode = '22023';
  end if;
  select * into p from public.proposals where token = p_token and status in ('enviada','visualizada','em_negociacao') for update;
  if not found then return false; end if;
  if p.valid_until is not null and p.valid_until < app.br_date(now()) then
    update public.proposals set status = 'expirada' where id = p.id;
    return false;
  end if;
  update public.proposals
     set status = 'aceita', accepted_by_name = btrim(p_name), accepted_by_email = lower(btrim(p_email)), accepted_ip = app.client_ip()
   where id = p.id;
  insert into public.proposal_events (proposal_id, kind, actor_name, ip, message)
  values (p.id, 'aceita', btrim(p_name), app.client_ip(), 'Aceite registrado pelo link da proposta (v' || p.version || ')');
  return true;
end $$;

create or replace function public.proposal_public_request_changes(p_token text, p_name text, p_message text) returns boolean
language plpgsql security definer set search_path = public as $$
declare p public.proposals;
begin
  if coalesce(btrim(p_message), '') = '' then raise exception 'Descreva as alterações desejadas' using errcode = '22023'; end if;
  select * into p from public.proposals where token = p_token and status in ('enviada','visualizada','em_negociacao') for update;
  if not found then return false; end if;
  update public.proposals set status = 'em_negociacao' where id = p.id;
  insert into public.proposal_events (proposal_id, kind, actor_name, ip, message)
  values (p.id, 'alteracao_solicitada', nullif(btrim(p_name), ''), app.client_ip(), left(p_message, 4000));
  perform app.notify('Alteração solicitada na proposta #' || p.number, left(p_message, 300), '/propostas/' || p.id, 'warning', null, null, null, p.agency_id);
  return true;
end $$;

drop function app.public_limit(text, text, text);
drop function app.rate_limit(text, int, int);
drop table public.public_rate_limits;
grant execute on function app.client_ip() to anon;
grant execute on function public.proposal_public_open(text), public.proposal_public_accept(text, text, text),
                          public.proposal_public_request_changes(text, text, text) to anon, authenticated;
