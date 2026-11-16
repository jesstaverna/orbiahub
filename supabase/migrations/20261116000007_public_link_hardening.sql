-- ORBIAHUB — 0007 Endurecimento do link público: limite de requisições (por token e por IP) e IP real do visitante.
--
-- * O app chama o banco a partir do servidor; sem repassar o IP do visitante, a "evidência" de aceite gravaria o IP do servidor.
--   Agora o app envia o cabeçalho x-client-ip; app.client_ip() o prefere (fallback: x-forwarded-for).
-- * Limite por TOKEN (não falsificável) e por IP (melhor esforço: quem chama o PostgREST direto pode forjar o cabeçalho).
--   Abrir a proposta acima do limite continua mostrando o conteúdo, mas não conta visualização nem grava evento.
--   Aceitar / pedir alteração acima do limite → erro P0429.

create table public.public_rate_limits (
  bucket        text        not null,
  window_start  timestamptz not null,
  hits          int         not null default 0,
  primary key (bucket, window_start)
);
alter table public.public_rate_limits enable row level security;   -- sem políticas: só funções definer
revoke all on public.public_rate_limits from anon, authenticated;
grant all on public.public_rate_limits to service_role;

-- Janela fixa. Retorna true se ainda está dentro do limite. Limpeza oportunista (1% das chamadas) de janelas antigas.
create or replace function app.rate_limit(p_bucket text, p_max int, p_window_seconds int) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_start timestamptz; v_hits int;
begin
  v_start := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  insert into public.public_rate_limits as r (bucket, window_start, hits) values (p_bucket, v_start, 1)
  on conflict (bucket, window_start) do update set hits = r.hits + 1
  returning hits into v_hits;
  if random() < 0.01 then delete from public.public_rate_limits where window_start < now() - interval '1 day'; end if;
  return v_hits <= p_max;
end $$;

create or replace function app.client_ip() returns text language sql stable as $$
  select nullif(btrim(coalesce(
    nullif(current_setting('request.headers', true)::json->>'x-client-ip', ''),
    split_part(coalesce(current_setting('request.headers', true)::json->>'x-forwarded-for', ''), ',', 1))), '')
$$;

-- Limites: abrir 120/10 min por token e 300/10 min por IP; aceitar/pedir alteração 10/10 min por token e 20/10 min por IP.
create or replace function app.public_limit(p_token text, p_ip text, p_action text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_tok int := case when p_action = 'open' then 120 else 10 end; v_ip int := case when p_action = 'open' then 300 else 20 end; ok boolean;
begin
  ok := app.rate_limit(p_action || ':t:' || md5(p_token), v_tok, 600);
  if p_ip is not null then ok := app.rate_limit(p_action || ':i:' || p_ip, v_ip, 600) and ok; end if;
  return ok;
end $$;

create or replace function public.proposal_public_open(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.proposals; v_items jsonb; v_agency jsonb; v_ok boolean;
begin
  select * into p from public.proposals where token = p_token and status <> 'rascunho';
  if not found then return null; end if;
  v_ok := app.public_limit(p_token, app.client_ip(), 'open');   -- acima do limite: só leitura, sem contar visualização

  if v_ok and p.valid_until is not null and p.valid_until < app.br_date(now()) and p.status in ('enviada','visualizada','em_negociacao') then
    update public.proposals set status = 'expirada' where id = p.id returning * into p;
  end if;

  if v_ok and p.status in ('enviada','visualizada','em_negociacao','aceita','expirada','recusada') then
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
  if not app.public_limit(p_token, app.client_ip(), 'accept') then raise exception 'Muitas tentativas. Aguarde alguns minutos.' using errcode = 'P0429'; end if;
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
  if not app.public_limit(p_token, app.client_ip(), 'changes') then raise exception 'Muitas tentativas. Aguarde alguns minutos.' using errcode = 'P0429'; end if;
  if coalesce(btrim(p_message), '') = '' then raise exception 'Descreva as alterações desejadas' using errcode = '22023'; end if;
  select * into p from public.proposals where token = p_token and status in ('enviada','visualizada','em_negociacao') for update;
  if not found then return false; end if;
  update public.proposals set status = 'em_negociacao' where id = p.id;
  insert into public.proposal_events (proposal_id, kind, actor_name, ip, message)
  values (p.id, 'alteracao_solicitada', nullif(btrim(p_name), ''), app.client_ip(), left(p_message, 4000));
  perform app.notify('Alteração solicitada na proposta #' || p.number, left(p_message, 300), '/propostas/' || p.id, 'warning', null, null, null, p.agency_id);
  return true;
end $$;

-- privilégios (mesmo modelo): novas funções app.* só para quem precisa
revoke execute on function app.rate_limit(text, int, int), app.public_limit(text, text, text) from public, anon;
grant execute on function app.rate_limit(text, int, int), app.public_limit(text, text, text) to authenticated, service_role;
grant execute on function app.client_ip() to anon, authenticated;
grant execute on function public.proposal_public_open(text), public.proposal_public_accept(text, text, text),
                          public.proposal_public_request_changes(text, text, text) to anon, authenticated;
