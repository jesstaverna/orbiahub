-- ORBIAHUB — rollback da 0006 (multi-tenant). Restaura o modelo single-tenant da 0001–0005.
-- GERADO a partir das migrações 0001–0005 (definições originais copiadas sem edição).
-- SEGURANÇA: só roda se existir no máximo 1 agência (com mais de uma, juntar os dados exigiria decisão humana). Faça backup antes.
do $$ begin
  if (select count(*) from public.agencies) > 1 then
    raise exception 'Rollback abortado: existem % agências. Consolide ou exporte os dados antes de reverter para single-tenant.', (select count(*) from public.agencies);
  end if;
end $$;

-- 1. políticas e triggers de tenant
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;
do $$ begin
  if to_regclass('storage.buckets') is not null then
    execute 'drop policy if exists "finance receipts read" on storage.objects';
    execute 'drop policy if exists "finance receipts write" on storage.objects';
    execute 'drop policy if exists "finance receipts delete" on storage.objects';
  end if;
end $$;
do $$ declare t text; begin
  foreach t in array array['clients', 'client_contacts', 'client_services', 'pipeline_stages', 'leads', 'lead_interactions', 'lead_reminders', 'proposals', 'proposal_items', 'proposal_versions', 'proposal_events', 'fin_categories', 'fin_recurring', 'fin_transactions', 'goals', 'notifications', 'profiles'] loop
    execute format('drop trigger if exists trg_00_agency_inherit on public.%I', t);
    execute format('drop trigger if exists trg_01_agency_guard on public.%I', t);
  end loop;
end $$;
drop trigger if exists trg_00_proposals_number on public.proposals;
drop trigger if exists trg_02_plan_limit_users on public.profiles;
drop trigger if exists trg_02_plan_limit_clients on public.clients;
drop trigger if exists trg_agencies_seed on public.agencies;
drop trigger if exists trg_agencies_audit on public.agencies;

-- 2. colunas de tenant (derruba índices/uniques/FKs que dependem delas)
do $$ declare t text; begin
  foreach t in array array['clients', 'client_contacts', 'client_services', 'pipeline_stages', 'leads', 'lead_interactions', 'lead_reminders', 'proposals', 'proposal_items', 'proposal_versions', 'proposal_events', 'fin_categories', 'fin_recurring', 'fin_transactions', 'goals', 'notifications', 'jobs', 'audit_log'] loop
    execute format('alter table public.%I drop column agency_id', t);
  end loop;
end $$;
alter table public.profiles drop column agency_id, drop column is_platform_admin;

-- 3. unicidades e numeração originais
create unique index clients_document_uidx on public.clients (regexp_replace(document, '\D', '', 'g')) where document is not null and document <> '';
create unique index leads_email_uidx on public.leads (email_norm) where email_norm is not null;
create unique index leads_phone_uidx on public.leads (phone_norm) where phone_norm is not null;
create unique index pipeline_stages_position_uidx on public.pipeline_stages (position) where active;
alter table public.fin_categories add constraint fin_categories_direction_name_key unique (direction, name);
alter table public.goals add constraint goals_period_type_period_start_key unique (period_type, period_start);
create sequence public.proposal_number_seq;
do $$ begin perform setval('public.proposal_number_seq', greatest((select coalesce(max(number), 0) from public.proposals), 1), (select count(*) > 0 from public.proposals)); end $$;
alter table public.proposals alter column number set default nextval('public.proposal_number_seq');
alter table public.proposals add constraint proposals_number_key unique (number);

-- 4. objetos novos
drop function app.proposals_number();
drop function app.agency_inherit();
drop function app.agency_guard();
drop function app.enforce_plan_limit();
drop function app.agencies_after_insert();
drop function app.seed_agency(uuid);
drop function app.next_counter(uuid, text);
drop function public.platform_create_agency(text, text, text, text);
drop function public.platform_set_agency(uuid, text, text);
drop function public.agency_add_member(text, text);
drop function app.notify(text, text, text, text, text, uuid, text, uuid);
drop function app.enqueue_job(text, jsonb, timestamptz, text, uuid);
drop table public.agency_counters;
drop table public.agencies;
drop table public.plans;
drop function app.current_agency_id();
drop function app.is_platform_admin();

-- 5. funções originais (copiadas das migrações 0001–0004)

create or replace function app.user_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(7000001);
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id, new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    case when exists (select 1 from public.profiles) then 'cliente' else 'admin' end
  );
  return new;
end $$;

create or replace function app.guard_profile() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated','anon') and not app.has_role('admin') then
    if new.role is distinct from old.role
       or new.client_id is distinct from old.client_id
       or new.active is distinct from old.active
       or new.id is distinct from old.id then
      raise exception 'Apenas administradores podem alterar papel, vínculo ou status do usuário' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create or replace function app.audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare rec jsonb;
begin
  rec := to_jsonb(coalesce(new, old));
  insert into public.audit_log (table_name, record_id, action, actor_id, old_data, new_data)
  values (tg_table_name, rec->>'id', tg_op, auth.uid(),
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create or replace function app.enqueue_job(p_type text, p_payload jsonb default '{}', p_run_at timestamptz default now(), p_dedupe text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.jobs (type, payload, run_at, dedupe_key) values (p_type, p_payload, p_run_at, p_dedupe)
  on conflict (dedupe_key) where dedupe_key is not null and status in ('pending','running') do nothing
  returning id into v_id;
  return v_id;
end $$;

create or replace function app.notify(p_title text, p_body text, p_link text, p_severity text default 'info',
                                      p_audience text default null, p_user uuid default null, p_dedupe text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (title, body, link, severity, audience, user_id, dedupe_key)
  values (p_title, p_body, p_link, p_severity, p_audience, p_user, p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

create or replace function app.leads_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.enqueue_job('lead.created', jsonb_build_object('lead_id', new.id), now(), 'lead.created:' || new.id);
  return new;
end $$;

create or replace function app.proposals_before() returns trigger language plpgsql as $$
declare v_gross numeric;
begin
  v_gross := new.subtotal_one_time + new.subtotal_monthly * new.contract_months;

  if tg_op = 'INSERT' or new.discount_value is distinct from old.discount_value then
    if new.discount_value > 0 then
      if current_user in ('authenticated','anon') then
        if not app.has_role('admin') then
          raise exception 'Descontos precisam ser autorizados por um administrador' using errcode = '42501';
        end if;
        new.discount_authorized_by := auth.uid();
      end if;
      if tg_op = 'UPDATE' and new.discount_value > v_gross then
        raise exception 'Desconto maior que o valor da proposta' using errcode = '23514';
      end if;
    else
      new.discount_authorized_by := null;
    end if;
  end if;

  new.total_value := greatest(v_gross - new.discount_value, 0);

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'enviada' and old.status = 'rascunho' then new.sent_at := coalesce(new.sent_at, now()); end if;
    if new.status = 'aceita' then
      new.accepted_at := coalesce(new.accepted_at, now());
      -- vira cliente automaticamente a partir do lead
      if new.client_id is null and new.lead_id is not null then
        insert into public.clients (name, legal_name, email, phone, segment)
        select coalesce(nullif(l.company, ''), l.name), nullif(l.company, ''), l.email, coalesce(l.whatsapp, l.phone), l.segment
          from public.leads l where l.id = new.lead_id
        returning id into new.client_id;
        update public.leads set client_id = new.client_id where id = new.lead_id;
      end if;
    end if;
    if new.status = 'recusada' then new.refused_at := coalesce(new.refused_at, now()); end if;
  end if;
  return new;
end $$;

create or replace function app.proposals_after() returns trigger language plpgsql security definer set search_path = public as $$
declare v_stage uuid;
begin
  if new.status is distinct from old.status then
    if new.status <> 'visualizada' then  -- visualizações têm evento próprio (com IP)
    insert into public.proposal_events (proposal_id, kind, message, created_by)
    values (new.id, case new.status when 'enviada' then 'enviada' when 'aceita' then 'aceita' when 'recusada' then 'recusada'
                                    when 'expirada' then 'expirada' else 'status_alterado' end,
            old.status || ' → ' || new.status, auth.uid());
    end if;

    if new.status = 'aceita' and new.lead_id is not null then
      select id into v_stage from public.pipeline_stages where kind = 'won' and active order by position limit 1;
      if v_stage is not null then update public.leads set stage_id = v_stage where id = new.lead_id and stage_id <> v_stage; end if;
    end if;
    if new.status = 'aceita' then
      perform app.enqueue_job('proposal.accepted', jsonb_build_object('proposal_id', new.id), now(), 'proposal.accepted:' || new.id);
      perform app.notify('Proposta #' || new.number || ' aceita',
                         new.client_display_name || ' aceitou "' || new.title || '". Prepare o contrato.',
                         '/propostas/' || new.id, 'info', null, null, 'proposal.accepted:' || new.id);
    end if;
    if new.status = 'enviada' and new.lead_id is not null then
      select id into v_stage from public.pipeline_stages where name = 'Proposta Enviada' and active limit 1;
      if v_stage is not null then
        update public.leads set stage_id = v_stage
         where id = new.lead_id and stage_id in (select id from public.pipeline_stages where kind = 'open' and position < (select position from public.pipeline_stages where id = v_stage));
      end if;
    end if;
  end if;
  return null;
end $$;

create or replace function public.proposal_public_open(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.proposals; v_items jsonb;
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

  return jsonb_build_object(
    'number', p.number, 'title', p.title, 'status', p.status, 'client_name', p.client_display_name,
    'content', p.content, 'payment_terms', p.payment_terms, 'installments', p.installments,
    'contract_months', p.contract_months, 'valid_until', p.valid_until, 'discount_value', p.discount_value,
    'subtotal_one_time', p.subtotal_one_time, 'subtotal_monthly', p.subtotal_monthly, 'total_value', p.total_value,
    'accepted_at', p.accepted_at, 'accepted_by_name', p.accepted_by_name, 'items', v_items);
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
  perform app.notify('Alteração solicitada na proposta #' || p.number, left(p_message, 300), '/propostas/' || p.id, 'warning', null, null, null);
  return true;
end $$;

create or replace function public.activate_proposal(p_id uuid, p_first_due date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.proposals; v_group uuid := gen_random_uuid(); v_cat_rec uuid; v_cat_one uuid;
        i int; v_each numeric; v_rest numeric; v_months int;
begin
  if not app.has_role('admin','financeiro') then
    raise exception 'Apenas administrador ou financeiro pode ativar uma proposta' using errcode = '42501';
  end if;
  select * into p from public.proposals where id = p_id for update;
  if not found then raise exception 'Proposta não encontrada'; end if;
  if p.status <> 'aceita' then raise exception 'Somente propostas aceitas podem ser ativadas' using errcode = '23514'; end if;
  if p.activated_at is not null then raise exception 'Proposta já ativada em %', p.activated_at using errcode = '23505'; end if;
  if p.client_id is null then raise exception 'Proposta sem cliente vinculado' using errcode = '23514'; end if;

  select id into v_cat_rec from public.fin_categories where direction = 'in' and name = 'Serviços recorrentes';
  select id into v_cat_one from public.fin_categories where direction = 'in' and name = 'Serviços pontuais';

  insert into public.client_services (client_id, proposal_id, service, billing, value, starts_on)
  select p.client_id, p.id, it.description, it.billing, it.line_total, p_first_due
    from public.proposal_items it where it.proposal_id = p.id;

  -- pontual: parcelado conforme a proposta (centavos restantes vão para a última parcela), menos o desconto
  if p.subtotal_one_time > 0 then
    v_rest := greatest(p.subtotal_one_time - p.discount_value, 0);
    v_each := round(v_rest / p.installments, 2);
    for i in 1..p.installments loop
      insert into public.fin_transactions (direction, description, category_id, client_id, proposal_id, amount, due_date, installment_no, installment_total, installment_group, created_by)
      values ('in', 'Proposta #' || p.number || ' — ' || p.title || ' (' || i || '/' || p.installments || ')', v_cat_one, p.client_id, p.id,
              case when i = p.installments then v_rest - v_each * (p.installments - 1) else v_each end,
              (p_first_due + ((i - 1) || ' months')::interval)::date, i, p.installments, v_group, auth.uid());
    end loop;
  end if;

  -- mensal: uma cobrança por mês de vigência
  if p.subtotal_monthly > 0 then
    v_months := p.contract_months;
    for i in 1..v_months loop
      insert into public.fin_transactions (direction, description, category_id, client_id, proposal_id, amount, due_date, installment_no, installment_total, installment_group, created_by)
      values ('in', 'Mensalidade proposta #' || p.number || ' (' || i || '/' || v_months || ')', v_cat_rec, p.client_id, p.id,
              p.subtotal_monthly, (p_first_due + ((i - 1) || ' months')::interval)::date, i, v_months, v_group, auth.uid());
    end loop;
  end if;

  update public.proposals set activated_at = now() where id = p.id;
  insert into public.proposal_events (proposal_id, kind, message, created_by) values (p.id, 'ativada', 'Cliente ativado e recebíveis previstos gerados', auth.uid());
  update public.clients set status = 'ativo' where id = p.client_id;
  return jsonb_build_object('client_id', p.client_id, 'group', v_group);
end $$;

create or replace function public.generate_recurring(p_month date) returns int
language plpgsql security invoker as $$
declare v_first date := date_trunc('month', p_month)::date; v_count int;
begin
  with ins as (
    insert into public.fin_transactions (direction, description, category_id, client_id, recurring_id, competence, amount, status, due_date, created_by)
    select r.direction,
           r.description || coalesce(' — ' || r.vendor, ''),
           r.category_id, r.client_id, r.id, v_first, r.amount, 'previsto',
           make_date(extract(year from v_first)::int, extract(month from v_first)::int,
                     least(r.day_of_month, extract(day from (v_first + interval '1 month - 1 day'))::int)),
           auth.uid()
      from public.fin_recurring r
     where r.active and r.starts_on <= (v_first + interval '1 month - 1 day')::date
       and (r.ends_on is null or r.ends_on >= v_first)
    on conflict (recurring_id, competence) where recurring_id is not null do nothing
    returning 1)
  select count(*) into v_count from ins;
  return v_count;
end $$;

create or replace function public.run_scheduled_scans() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n_over int := 0; n_leads int := 0; n_props int := 0; n_rem int := 0; n_exp int := 0; n_gen int := 0; rec record; today date := app.br_date(now());
begin
  -- Pagamentos em atraso
  for rec in select t.id, t.description, t.amount, t.due_date from public.fin_transactions t
              where t.direction = 'in' and t.status in ('previsto','emitido') and t.due_date < today loop
    perform app.notify('Pagamento em atraso', rec.description || ' — R$ ' || to_char(rec.amount, 'FM999G999G990D00') || ' (venc. ' || to_char(rec.due_date, 'DD/MM/YYYY') || ')',
                       '/financeiro?tab=receber', 'critical', 'financeiro', null, 'overdue:' || rec.id);
    n_over := n_over + 1;
  end loop;

  -- Oportunidades abertas sem contato há 3+ dias
  for rec in select l.id, l.name, l.owner_id from public.leads l join public.pipeline_stages s on s.id = l.stage_id
              where s.kind = 'open' and coalesce(l.last_contact_at, l.created_at) < now() - interval '3 days' loop
    perform app.notify('Oportunidade sem acompanhamento', rec.name || ' está há mais de 3 dias sem contato.', '/crm/' || rec.id, 'warning',
                       case when rec.owner_id is null then 'comercial' end, rec.owner_id,
                       'stale-lead:' || rec.id || ':' || to_char(today, 'IYYY-IW'));
    n_leads := n_leads + 1;
  end loop;

  -- Propostas enviadas há 5+ dias sem resposta
  for rec in select p.id, p.number, p.client_display_name, p.owner_id from public.proposals p
              where p.status in ('enviada','visualizada') and p.sent_at < now() - interval '5 days' loop
    perform app.notify('Proposta parada', 'Proposta #' || rec.number || ' (' || rec.client_display_name || ') sem resposta há mais de 5 dias.',
                       '/propostas/' || rec.id, 'warning', case when rec.owner_id is null then 'comercial' end, rec.owner_id,
                       'stale-proposal:' || rec.id || ':' || to_char(today, 'IYYY-IW'));
    n_props := n_props + 1;
  end loop;

  -- Lembretes vencidos
  for rec in select r.id, r.title, r.lead_id, coalesce(r.assigned_to, r.created_by) as uid from public.lead_reminders r
              where r.done_at is null and r.due_at <= now() loop
    perform app.notify('Lembrete: ' || rec.title, null, '/crm/' || rec.lead_id, 'info', case when rec.uid is null then 'comercial' end, rec.uid, 'reminder:' || rec.id);
    n_rem := n_rem + 1;
  end loop;

  -- Propostas expiradas
  update public.proposals set status = 'expirada'
   where status in ('enviada','visualizada','em_negociacao') and valid_until is not null and valid_until < today;
  get diagnostics n_exp = row_count;

  -- Despesas fixas/assinaturas/receitas recorrentes do mês corrente
  n_gen := public.generate_recurring(today);

  return jsonb_build_object('recurring_generated', n_gen, 'overdue', n_over, 'stale_leads', n_leads, 'stale_proposals', n_props, 'reminders', n_rem, 'expired_proposals', n_exp);
end $$;


-- 6. sementes globais (banco que não tinha agência volta a ter funil e categorias padrão)
do $$ begin
  if not exists (select 1 from public.pipeline_stages) then
insert into public.pipeline_stages (name, position, kind, probability, is_negotiation) values
  ('Novo Lead',               1, 'open',  5,  false),
  ('Primeiro Contato',        2, 'open',  10, false),
  ('Qualificação',            3, 'open',  20, false),
  ('Reunião',                 4, 'open',  35, false),
  ('Proposta em Elaboração',  5, 'open',  45, false),
  ('Proposta Enviada',        6, 'open',  55, false),
  ('Em Negociação',           7, 'open',  70, true),
  ('Fechado',                 8, 'won',   100, false),
  ('Não Fechado',             9, 'lost',  0,  false);
  end if;
  if not exists (select 1 from public.fin_categories) then
insert into public.fin_categories (name, direction, expense_type) values
  ('Serviços recorrentes',      'in',  null),
  ('Serviços pontuais',         'in',  null),
  ('Outras receitas',           'in',  null),
  ('Pró-labore',                'out', 'prolabore'),
  ('Impostos',                  'out', 'imposto'),
  ('Ferramentas e assinaturas', 'out', 'fixa'),
  ('Escritório e infraestrutura','out','fixa'),
  ('Freelancers e terceiros',   'out', 'variavel'),
  ('Marketing próprio',         'out', 'variavel'),
  ('Taxas bancárias e cobrança','out', 'variavel');
  end if;
end $$;

-- 7. políticas e storage originais (0005)
-- profiles
create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or app.is_staff());
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated using (app.has_role('admin')) with check (app.has_role('admin'));

-- audit_log / jobs: somente admin lê; escrita só via triggers/funções definer e service role
create policy audit_select on public.audit_log for select to authenticated using (app.has_role('admin'));
create policy jobs_select on public.jobs for select to authenticated using (app.has_role('admin'));

-- notifications: equipe vê as endereçadas a ela, ao seu papel ou a todos
create policy notif_select on public.notifications for select to authenticated
  using (app.is_staff() and (user_id = auth.uid() or (user_id is null and (audience is null or audience = app.user_role()))));
create policy notif_update on public.notifications for update to authenticated
  using (app.is_staff() and (user_id = auth.uid() or (user_id is null and (audience is null or audience = app.user_role()))))
  with check (app.is_staff());

-- clientes (designer/tráfego precisam enxergar; edição por admin/comercial/financeiro)
create policy clients_select on public.clients for select to authenticated using (app.is_staff() or id = app.current_client_id());
create policy clients_write on public.clients for all to authenticated
  using (app.has_role('admin','comercial','financeiro')) with check (app.has_role('admin','comercial','financeiro'));
create policy contacts_select on public.client_contacts for select to authenticated using (app.is_staff());
create policy contacts_write on public.client_contacts for all to authenticated
  using (app.has_role('admin','comercial','financeiro')) with check (app.has_role('admin','comercial','financeiro'));
create policy cservices_select on public.client_services for select to authenticated using (app.has_role('admin','comercial','financeiro'));
create policy cservices_write on public.client_services for all to authenticated
  using (app.has_role('admin','financeiro')) with check (app.has_role('admin','financeiro'));

-- CRM
create policy stages_select on public.pipeline_stages for select to authenticated using (app.is_staff());
create policy stages_write on public.pipeline_stages for all to authenticated using (app.has_role('admin')) with check (app.has_role('admin'));
create policy leads_all on public.leads for all to authenticated
  using (app.has_role('admin','comercial')) with check (app.has_role('admin','comercial'));
create policy interactions_all on public.lead_interactions for all to authenticated
  using (app.has_role('admin','comercial')) with check (app.has_role('admin','comercial'));
create policy reminders_all on public.lead_reminders for all to authenticated
  using (app.has_role('admin','comercial')) with check (app.has_role('admin','comercial'));

-- propostas (financeiro só lê)
create policy proposals_select on public.proposals for select to authenticated using (app.has_role('admin','comercial','financeiro'));
create policy proposals_write on public.proposals for all to authenticated using (app.has_role('admin','comercial')) with check (app.has_role('admin','comercial'));
create policy pitems_select on public.proposal_items for select to authenticated using (app.has_role('admin','comercial','financeiro'));
create policy pitems_write on public.proposal_items for all to authenticated using (app.has_role('admin','comercial')) with check (app.has_role('admin','comercial'));
create policy pversions_select on public.proposal_versions for select to authenticated using (app.has_role('admin','comercial','financeiro'));
create policy pversions_insert on public.proposal_versions for insert to authenticated with check (app.has_role('admin','comercial'));
create policy pevents_select on public.proposal_events for select to authenticated using (app.has_role('admin','comercial','financeiro'));
create policy pevents_insert on public.proposal_events for insert to authenticated with check (app.has_role('admin','comercial'));

-- financeiro
create policy fincat_select on public.fin_categories for select to authenticated using (app.has_role('admin','financeiro','comercial'));
create policy fincat_write on public.fin_categories for all to authenticated using (app.has_role('admin','financeiro')) with check (app.has_role('admin','financeiro'));
create policy finrec_all on public.fin_recurring for all to authenticated using (app.has_role('admin','financeiro')) with check (app.has_role('admin','financeiro'));
create policy fintx_all on public.fin_transactions for all to authenticated using (app.has_role('admin','financeiro')) with check (app.has_role('admin','financeiro'));

-- metas
create policy goals_select on public.goals for select to authenticated using (app.has_role('admin','comercial','financeiro'));
create policy goals_write on public.goals for all to authenticated using (app.has_role('admin')) with check (app.has_role('admin'));


-- ---------- storage privado (comprovantes) — só existe no Supabase ----------
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public) values ('finance-receipts', 'finance-receipts', false) on conflict (id) do nothing;
    execute $p$create policy "finance receipts read" on storage.objects for select to authenticated
      using (bucket_id = 'finance-receipts' and app.has_role('admin','financeiro'))$p$;
    execute $p$create policy "finance receipts write" on storage.objects for insert to authenticated
      with check (bucket_id = 'finance-receipts' and app.has_role('admin','financeiro'))$p$;
    execute $p$create policy "finance receipts delete" on storage.objects for delete to authenticated
      using (bucket_id = 'finance-receipts' and app.has_role('admin','financeiro'))$p$;
  end if;
end $$;

-- 8. privilégios originais
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
revoke all on all sequences in schema public from anon;
grant usage on all sequences in schema public to authenticated;
grant all on all sequences in schema public to service_role;
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
grant execute on function public.proposal_public_open(text), public.proposal_public_accept(text, text, text),
                          public.proposal_public_request_changes(text, text, text) to anon, authenticated;
grant execute on function public.dashboard_metrics(date, date, uuid), public.finance_monthly_series(int), public.crm_conversion(date, date),
                          public.generate_recurring(date), public.activate_proposal(uuid, date), public.proposal_snapshot(uuid, text) to authenticated;
grant execute on function public.claim_jobs(int), public.finish_job(uuid, text), public.run_scheduled_scans() to service_role;
grant execute on function app.client_ip(), app.br_date(timestamptz), app.norm_email(text), app.norm_phone(text), app.has_role(text[]), app.user_role() to anon;
grant execute on function app.notify(text, text, text, text, text, uuid, text), app.enqueue_job(text, jsonb, timestamptz, text) to anon;
