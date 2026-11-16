-- ORBIAHUB — 0006 Multi-tenant: agências, planos, isolamento por agência (RLS), integridade entre tenants
--
-- Decisões (ver docs/DECISOES.md):
--  * 1 usuário pertence a 1 agência (profiles.agency_id). Papéis continuam em profiles.role (admin = proprietário/administrador da agência).
--  * Administrador da plataforma = profiles.is_platform_admin. Ele gerencia agências/planos, mas NÃO lê dados de negócio das agências (LGPD).
--  * Todo dado de negócio carrega agency_id; RLS filtra por app.current_agency_id(); triggers impedem referências entre agências.
--  * Migração segura: se já existem dados (instalação single-tenant), eles são atribuídos a uma agência "Agência padrão".
--  * Reversível: supabase/rollback/20261116000006_multitenancy.down.sql (só se houver no máximo 1 agência).

-- =====================================================================================================
-- A. Planos e agências
-- =====================================================================================================
create table public.plans (
  key          text primary key,
  name         text not null,
  max_users    int  check (max_users   is null or max_users   > 0),   -- null = ilimitado
  max_clients  int  check (max_clients is null or max_clients > 0),
  active       boolean not null default true,                         -- plano disponível para novas agências
  created_at   timestamptz not null default now()
);
-- Limites de EXEMPLO, editáveis. Não representam preço nem proposta comercial: servem para a estrutura de cobrança futura.
insert into public.plans (key, name, max_users, max_clients, active) values
  ('trial',    'Teste',    3,    10,   true),
  ('start',    'Start',    5,    30,   true),
  ('pro',      'Pro',      15,   150,  true),
  ('scale',    'Scale',    null, null, true),
  ('internal', 'Interno',  null, null, false);

create table public.agencies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (btrim(name) <> ''),
  slug        text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  plan        text not null default 'trial' references public.plans(key),
  status      text not null default 'active' check (status in ('active','suspended')),
  brand       jsonb not null default '{}'::jsonb,          -- identidade visual da agência (cores, logo_path...)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_agencies_touch before update on public.agencies for each row execute function app.touch_updated_at();

alter table public.profiles
  add column agency_id uuid references public.agencies(id) on delete restrict,
  add column is_platform_admin boolean not null default false;
create index profiles_agency_idx on public.profiles (agency_id);

-- Contadores por agência (ex.: número sequencial das propostas é por agência, não global)
create table public.agency_counters (
  agency_id uuid not null references public.agencies(id) on delete cascade,
  key       text not null,
  value     int  not null default 0,
  primary key (agency_id, key)
);
create or replace function app.next_counter(p_agency uuid, p_key text) returns int
language sql security definer set search_path = public as $$
  insert into public.agency_counters (agency_id, key, value) values (p_agency, p_key, 1)
  on conflict (agency_id, key) do update set value = public.agency_counters.value + 1
  returning value
$$;

-- =====================================================================================================
-- B. Helpers de contexto
-- =====================================================================================================
-- Agência do usuário logado; NULL se não tiver agência, estiver inativo ou a agência estiver suspensa.
create or replace function app.current_agency_id() returns uuid
language sql stable security definer set search_path = public as $$
  select p.agency_id from public.profiles p join public.agencies a on a.id = p.agency_id
   where p.id = auth.uid() and p.active and a.status = 'active'
$$;

create or replace function app.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.is_platform_admin from public.profiles p where p.id = auth.uid() and p.active), false)
$$;

-- Papel só vale dentro de uma agência ativa.
create or replace function app.user_role() returns text
language sql stable security definer set search_path = public as $$
  select p.role from public.profiles p join public.agencies a on a.id = p.agency_id
   where p.id = auth.uid() and p.active and a.status = 'active'
$$;

-- =====================================================================================================
-- C. agency_id em todas as tabelas de negócio (com backfill seguro)
-- =====================================================================================================
do $$
declare
  v_legacy uuid; t text;
  tenant text[] := array['clients','client_contacts','client_services','pipeline_stages','leads','lead_interactions','lead_reminders',
                         'proposals','proposal_items','proposal_versions','proposal_events','fin_categories','fin_recurring',
                         'fin_transactions','goals','notifications'];
  loose  text[] := array['jobs','audit_log'];
begin
  if exists (select 1 from public.profiles) or exists (select 1 from public.clients) or exists (select 1 from public.leads) then
    -- instalação single-tenant com dados: tudo vai para uma agência padrão (sem disparar triggers: coluna nova com DEFAULT constante)
    insert into public.agencies (name, slug, plan) values ('Agência padrão', 'agencia-padrao', 'internal') returning id into v_legacy;
    alter table public.profiles disable trigger user;
    update public.profiles set agency_id = v_legacy;
    -- o operador da instalação single-tenant (admin mais antigo) passa a ser administrador da plataforma
    update public.profiles set is_platform_admin = true
     where id = (select id from public.profiles where role = 'admin' and active order by created_at, id limit 1);
    alter table public.profiles enable trigger user;
  else
    -- banco novo: as sementes globais viram sementes por agência (app.seed_agency)
    delete from public.pipeline_stages;
    delete from public.fin_categories;
  end if;

  foreach t in array tenant loop
    if v_legacy is null then
      execute format('alter table public.%I add column agency_id uuid not null references public.agencies(id) on delete restrict', t);
    else
      execute format('alter table public.%I add column agency_id uuid not null default %L references public.agencies(id) on delete restrict', t, v_legacy);
      execute format('alter table public.%I alter column agency_id drop default', t);
    end if;
    execute format('create index %I on public.%I (agency_id)', t || '_agency_idx', t);
  end loop;

  foreach t in array loose loop
    if v_legacy is null then
      execute format('alter table public.%I add column agency_id uuid references public.agencies(id) on delete set null', t);
    else
      execute format('alter table public.%I add column agency_id uuid default %L references public.agencies(id) on delete set null', t, v_legacy);
      execute format('alter table public.%I alter column agency_id drop default', t);
    end if;
    execute format('create index %I on public.%I (agency_id)', t || '_agency_idx', t);
  end loop;

  if v_legacy is not null then
    insert into public.agency_counters (agency_id, key, value)
      select v_legacy, 'proposal', coalesce(max(number), 0) from public.proposals;
  end if;
end $$;

-- Tabelas "raiz": agência vem do usuário logado. Tabelas "filhas": herdam do registro pai (trigger abaixo).
alter table public.clients          alter column agency_id set default app.current_agency_id();
alter table public.pipeline_stages  alter column agency_id set default app.current_agency_id();
alter table public.leads            alter column agency_id set default app.current_agency_id();
alter table public.proposals        alter column agency_id set default app.current_agency_id();
alter table public.fin_categories   alter column agency_id set default app.current_agency_id();
alter table public.fin_recurring    alter column agency_id set default app.current_agency_id();
alter table public.fin_transactions alter column agency_id set default app.current_agency_id();
alter table public.goals            alter column agency_id set default app.current_agency_id();
alter table public.notifications    alter column agency_id set default app.current_agency_id();

-- =====================================================================================================
-- D. Unicidade por agência
-- =====================================================================================================
drop index public.clients_document_uidx;
create unique index clients_document_uidx on public.clients (agency_id, regexp_replace(document, '\D', '', 'g')) where document is not null and document <> '';
drop index public.leads_email_uidx;
create unique index leads_email_uidx on public.leads (agency_id, email_norm) where email_norm is not null;
drop index public.leads_phone_uidx;
create unique index leads_phone_uidx on public.leads (agency_id, phone_norm) where phone_norm is not null;
drop index public.pipeline_stages_position_uidx;
create unique index pipeline_stages_position_uidx on public.pipeline_stages (agency_id, position) where active;
alter table public.fin_categories drop constraint fin_categories_direction_name_key;
alter table public.fin_categories add constraint fin_categories_agency_direction_name_key unique (agency_id, direction, name);
alter table public.goals drop constraint goals_period_type_period_start_key;
alter table public.goals add constraint goals_agency_period_key unique (agency_id, period_type, period_start);

-- Número da proposta: sequencial por agência
alter table public.proposals drop constraint proposals_number_key;
alter table public.proposals alter column number drop default;
drop sequence public.proposal_number_seq;
alter table public.proposals add constraint proposals_agency_number_key unique (agency_id, number);
create or replace function app.proposals_number() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.number is null then new.number := app.next_counter(new.agency_id, 'proposal'); end if;
  return new;
end $$;
create trigger trg_00_proposals_number before insert on public.proposals for each row execute function app.proposals_number();

-- =====================================================================================================
-- E. Integridade entre tenants (triggers)
-- =====================================================================================================
-- Filha herda agency_id do pai; se vier outro valor, recusa.
create or replace function app.agency_inherit() returns trigger language plpgsql security definer set search_path = public as $$
declare v_fk text := tg_argv[0]; v_tbl text := tg_argv[1]; v_val uuid; v_agency uuid; v_n int;
begin
  v_val := (to_jsonb(new) ->> v_fk)::uuid;
  if v_val is null then return new; end if;
  execute format('select agency_id from public.%I where id = $1', v_tbl) into v_agency using v_val;
  get diagnostics v_n = row_count;   -- EXECUTE não atualiza FOUND
  if v_n = 0 then raise exception 'Registro relacionado inexistente (%.%)', tg_table_name, v_fk using errcode = '23503'; end if;
  if new.agency_id is null then new.agency_id := v_agency;
  elsif new.agency_id <> v_agency then raise exception 'Referência entre agências diferentes (%.%)', tg_table_name, v_fk using errcode = '42501';
  end if;
  return new;
end $$;

-- Impede mover registro de agência e referenciar registros de outra agência (FKs "col:tabela" em TG_ARGV).
create or replace function app.agency_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare spec text; v_col text; v_tbl text; v_val uuid; v_agency uuid; v_n int;
begin
  if tg_op = 'UPDATE' and new.agency_id is distinct from old.agency_id and current_user in ('authenticated','anon') then
    raise exception 'Registros não podem mudar de agência' using errcode = '42501';
  end if;
  foreach spec in array coalesce(tg_argv, '{}'::text[]) loop
    v_col := split_part(spec, ':', 1); v_tbl := split_part(spec, ':', 2);
    v_val := (to_jsonb(new) ->> v_col)::uuid;
    if v_val is null then continue; end if;
    execute format('select agency_id from public.%I where id = $1', v_tbl) into v_agency using v_val;
    get diagnostics v_n = row_count;
    if v_n > 0 and v_agency is distinct from new.agency_id then
      raise exception 'Referência entre agências diferentes (%.%)', tg_table_name, v_col using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;

create trigger trg_00_agency_inherit before insert on public.client_contacts   for each row execute function app.agency_inherit('client_id', 'clients');
create trigger trg_00_agency_inherit before insert on public.client_services   for each row execute function app.agency_inherit('client_id', 'clients');
create trigger trg_00_agency_inherit before insert on public.lead_interactions for each row execute function app.agency_inherit('lead_id', 'leads');
create trigger trg_00_agency_inherit before insert on public.lead_reminders    for each row execute function app.agency_inherit('lead_id', 'leads');
create trigger trg_00_agency_inherit before insert on public.proposal_items    for each row execute function app.agency_inherit('proposal_id', 'proposals');
create trigger trg_00_agency_inherit before insert on public.proposal_versions for each row execute function app.agency_inherit('proposal_id', 'proposals');
create trigger trg_00_agency_inherit before insert on public.proposal_events   for each row execute function app.agency_inherit('proposal_id', 'proposals');

create trigger trg_01_agency_guard before insert or update on public.clients          for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.client_contacts  for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.client_services  for each row execute function app.agency_guard('proposal_id:proposals');
create trigger trg_01_agency_guard before insert or update on public.pipeline_stages  for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.leads            for each row execute function app.agency_guard('client_id:clients', 'owner_id:profiles', 'stage_id:pipeline_stages');
create trigger trg_01_agency_guard before insert or update on public.lead_interactions for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.lead_reminders   for each row execute function app.agency_guard('assigned_to:profiles');
create trigger trg_01_agency_guard before insert or update on public.proposals        for each row execute function app.agency_guard('lead_id:leads', 'client_id:clients', 'owner_id:profiles');
create trigger trg_01_agency_guard before insert or update on public.proposal_items   for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.proposal_versions for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.proposal_events  for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.fin_categories   for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.fin_recurring    for each row execute function app.agency_guard('client_id:clients', 'category_id:fin_categories');
create trigger trg_01_agency_guard before insert or update on public.fin_transactions for each row execute function app.agency_guard('client_id:clients', 'category_id:fin_categories', 'proposal_id:proposals', 'recurring_id:fin_recurring');
create trigger trg_01_agency_guard before insert or update on public.goals            for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.notifications    for each row execute function app.agency_guard('user_id:profiles');
create trigger trg_01_agency_guard before insert or update on public.profiles         for each row execute function app.agency_guard('client_id:clients');

-- =====================================================================================================
-- F. Perfis: onboarding, anti-escalada e limites do plano
-- =====================================================================================================
-- O primeiro usuário do sistema vira administrador da PLATAFORMA. Demais entram sem agência = sem acesso a nada,
-- até serem vinculados por agency_add_member / platform_create_agency. (Nunca confiar em user_metadata: é editável pelo usuário.)
create or replace function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_first boolean;
begin
  perform pg_advisory_xact_lock(7000001);
  v_first := not exists (select 1 from public.profiles);
  insert into public.profiles (id, email, full_name, role, is_platform_admin)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
          case when v_first then 'admin' else 'cliente' end, v_first);
  return new;
end $$;

create or replace function app.guard_profile() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated','anon') then
    if new.agency_id is distinct from old.agency_id or new.is_platform_admin is distinct from old.is_platform_admin then
      raise exception 'Vínculo com a agência e perfil de plataforma só podem ser alterados pela plataforma' using errcode = '42501';
    end if;
    if not app.has_role('admin') and (new.role is distinct from old.role or new.client_id is distinct from old.client_id
         or new.active is distinct from old.active or new.id is distinct from old.id) then
      raise exception 'Apenas administradores podem alterar papel, vínculo ou status do usuário' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create or replace function app.enforce_plan_limit() returns trigger language plpgsql security definer set search_path = public as $$
declare v_max int; v_cnt int;
begin
  if new.agency_id is null then return new; end if;
  if tg_argv[0] = 'users' then
    if not new.active then return new; end if;
    if tg_op = 'UPDATE' and old.agency_id is not distinct from new.agency_id and old.active then return new; end if;  -- só ao entrar na agência/reativar
    select pl.max_users into v_max from public.agencies a join public.plans pl on pl.key = a.plan where a.id = new.agency_id;
    select count(*) into v_cnt from public.profiles where agency_id = new.agency_id and active and id <> new.id;
  else
    select pl.max_clients into v_max from public.agencies a join public.plans pl on pl.key = a.plan where a.id = new.agency_id;
    select count(*) into v_cnt from public.clients where agency_id = new.agency_id and status <> 'encerrado';
  end if;
  if v_max is not null and v_cnt >= v_max then
    raise exception 'Limite do plano atingido (%). Faça upgrade para continuar.', tg_argv[0] using errcode = '53400';
  end if;
  return new;
end $$;
create trigger trg_02_plan_limit_users   before insert or update on public.profiles for each row execute function app.enforce_plan_limit('users');
create trigger trg_02_plan_limit_clients before insert on public.clients           for each row execute function app.enforce_plan_limit('clients');

-- =====================================================================================================
-- G. Sementes por agência (funil e categorias financeiras)
-- =====================================================================================================
create or replace function app.seed_agency(p_agency uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.pipeline_stages where agency_id = p_agency) then
    insert into public.pipeline_stages (agency_id, name, position, kind, probability, is_negotiation) values
      (p_agency, 'Novo Lead',               1, 'open',  5,   false),
      (p_agency, 'Primeiro Contato',        2, 'open',  10,  false),
      (p_agency, 'Qualificação',            3, 'open',  20,  false),
      (p_agency, 'Reunião',                 4, 'open',  35,  false),
      (p_agency, 'Proposta em Elaboração',  5, 'open',  45,  false),
      (p_agency, 'Proposta Enviada',        6, 'open',  55,  false),
      (p_agency, 'Em Negociação',           7, 'open',  70,  true),
      (p_agency, 'Fechado',                 8, 'won',   100, false),
      (p_agency, 'Não Fechado',             9, 'lost',  0,   false);
  end if;
  if not exists (select 1 from public.fin_categories where agency_id = p_agency) then
    insert into public.fin_categories (agency_id, name, direction, expense_type) values
      (p_agency, 'Serviços recorrentes',       'in',  null),
      (p_agency, 'Serviços pontuais',          'in',  null),
      (p_agency, 'Outras receitas',            'in',  null),
      (p_agency, 'Pró-labore',                 'out', 'prolabore'),
      (p_agency, 'Impostos',                   'out', 'imposto'),
      (p_agency, 'Ferramentas e assinaturas',  'out', 'fixa'),
      (p_agency, 'Escritório e infraestrutura','out', 'fixa'),
      (p_agency, 'Freelancers e terceiros',    'out', 'variavel'),
      (p_agency, 'Marketing próprio',          'out', 'variavel'),
      (p_agency, 'Taxas bancárias e cobrança', 'out', 'variavel');
  end if;
end $$;
create or replace function app.agencies_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin perform app.seed_agency(new.id); return null; end $$;
create trigger trg_agencies_seed after insert on public.agencies for each row execute function app.agencies_after_insert();
create trigger trg_agencies_audit after insert or update or delete on public.agencies for each row execute function app.audit();

-- =====================================================================================================
-- H. Funções reescritas com escopo de agência
-- =====================================================================================================
create or replace function app.audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare rec jsonb;
begin
  rec := to_jsonb(coalesce(new, old));
  insert into public.audit_log (table_name, record_id, action, actor_id, old_data, new_data, agency_id)
  values (tg_table_name, rec->>'id', tg_op, auth.uid(),
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
          case when tg_table_name = 'agencies' then (rec->>'id')::uuid else nullif(rec->>'agency_id', '')::uuid end);
  return coalesce(new, old);
end $$;

drop function app.enqueue_job(text, jsonb, timestamptz, text);
create or replace function app.enqueue_job(p_type text, p_payload jsonb default '{}', p_run_at timestamptz default now(), p_dedupe text default null, p_agency uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.jobs (type, payload, run_at, dedupe_key, agency_id) values (p_type, p_payload, p_run_at, p_dedupe, p_agency)
  on conflict (dedupe_key) where dedupe_key is not null and status in ('pending','running') do nothing
  returning id into v_id;
  return v_id;
end $$;

drop function app.notify(text, text, text, text, text, uuid, text);
create or replace function app.notify(p_title text, p_body text, p_link text, p_severity text default 'info',
                                      p_audience text default null, p_user uuid default null, p_dedupe text default null, p_agency uuid default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (agency_id, title, body, link, severity, audience, user_id, dedupe_key)
  values (coalesce(p_agency, app.current_agency_id()), p_title, p_body, p_link, p_severity, p_audience, p_user, p_dedupe)
  on conflict (dedupe_key) do nothing;
end $$;

create or replace function app.leads_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform app.enqueue_job('lead.created', jsonb_build_object('lead_id', new.id), now(), 'lead.created:' || new.id, new.agency_id);
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
      -- vira cliente automaticamente a partir do lead (na MESMA agência da proposta)
      if new.client_id is null and new.lead_id is not null then
        insert into public.clients (agency_id, name, legal_name, email, phone, segment)
        select new.agency_id, coalesce(nullif(l.company, ''), l.name), nullif(l.company, ''), l.email, coalesce(l.whatsapp, l.phone), l.segment
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
    if new.status <> 'visualizada' then
    insert into public.proposal_events (proposal_id, kind, message, created_by)
    values (new.id, case new.status when 'enviada' then 'enviada' when 'aceita' then 'aceita' when 'recusada' then 'recusada'
                                    when 'expirada' then 'expirada' else 'status_alterado' end,
            old.status || ' → ' || new.status, auth.uid());
    end if;

    if new.status = 'aceita' and new.lead_id is not null then
      select id into v_stage from public.pipeline_stages where agency_id = new.agency_id and kind = 'won' and active order by position limit 1;
      if v_stage is not null then update public.leads set stage_id = v_stage where id = new.lead_id and stage_id <> v_stage; end if;
    end if;
    if new.status = 'aceita' then
      perform app.enqueue_job('proposal.accepted', jsonb_build_object('proposal_id', new.id), now(), 'proposal.accepted:' || new.id, new.agency_id);
      perform app.notify('Proposta #' || new.number || ' aceita',
                         new.client_display_name || ' aceitou "' || new.title || '". Prepare o contrato.',
                         '/propostas/' || new.id, 'info', null, null, 'proposal.accepted:' || new.id, new.agency_id);
    end if;
    if new.status = 'enviada' and new.lead_id is not null then
      select id into v_stage from public.pipeline_stages where agency_id = new.agency_id and name = 'Proposta Enviada' and active limit 1;
      if v_stage is not null then
        update public.leads set stage_id = v_stage
         where id = new.lead_id and stage_id in (select id from public.pipeline_stages where agency_id = new.agency_id and kind = 'open'
                                                  and position < (select position from public.pipeline_stages where id = v_stage));
      end if;
    end if;
  end if;
  return null;
end $$;

-- Link público: devolve também a identidade da agência (nome/cores) para renderizar a proposta com a marca dela.
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

create or replace function public.activate_proposal(p_id uuid, p_first_due date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.proposals; v_group uuid := gen_random_uuid(); v_cat_rec uuid; v_cat_one uuid;
        i int; v_each numeric; v_rest numeric; v_months int;
begin
  if not app.has_role('admin','financeiro') then
    raise exception 'Apenas administrador ou financeiro pode ativar uma proposta' using errcode = '42501';
  end if;
  -- escopo de agência: uma proposta de outra agência é tratada como inexistente
  select * into p from public.proposals where id = p_id and agency_id = app.current_agency_id() for update;
  if not found then raise exception 'Proposta não encontrada'; end if;
  if p.status <> 'aceita' then raise exception 'Somente propostas aceitas podem ser ativadas' using errcode = '23514'; end if;
  if p.activated_at is not null then raise exception 'Proposta já ativada em %', p.activated_at using errcode = '23505'; end if;
  if p.client_id is null then raise exception 'Proposta sem cliente vinculado' using errcode = '23514'; end if;

  select id into v_cat_rec from public.fin_categories where agency_id = p.agency_id and direction = 'in' and name = 'Serviços recorrentes';
  select id into v_cat_one from public.fin_categories where agency_id = p.agency_id and direction = 'in' and name = 'Serviços pontuais';

  insert into public.client_services (agency_id, client_id, proposal_id, service, billing, value, starts_on)
  select p.agency_id, p.client_id, p.id, it.description, it.billing, it.line_total, p_first_due
    from public.proposal_items it where it.proposal_id = p.id;

  if p.subtotal_one_time > 0 then
    v_rest := greatest(p.subtotal_one_time - p.discount_value, 0);
    v_each := round(v_rest / p.installments, 2);
    for i in 1..p.installments loop
      insert into public.fin_transactions (agency_id, direction, description, category_id, client_id, proposal_id, amount, due_date, installment_no, installment_total, installment_group, created_by)
      values (p.agency_id, 'in', 'Proposta #' || p.number || ' — ' || p.title || ' (' || i || '/' || p.installments || ')', v_cat_one, p.client_id, p.id,
              case when i = p.installments then v_rest - v_each * (p.installments - 1) else v_each end,
              (p_first_due + ((i - 1) || ' months')::interval)::date, i, p.installments, v_group, auth.uid());
    end loop;
  end if;

  if p.subtotal_monthly > 0 then
    v_months := p.contract_months;
    for i in 1..v_months loop
      insert into public.fin_transactions (agency_id, direction, description, category_id, client_id, proposal_id, amount, due_date, installment_no, installment_total, installment_group, created_by)
      values (p.agency_id, 'in', 'Mensalidade proposta #' || p.number || ' (' || i || '/' || v_months || ')', v_cat_rec, p.client_id, p.id,
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
    insert into public.fin_transactions (agency_id, direction, description, category_id, client_id, recurring_id, competence, amount, status, due_date, created_by)
    select r.agency_id, r.direction,
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

-- Varreduras do worker: percorre TODAS as agências ativas (service role), sempre notificando na agência do registro.
create or replace function public.run_scheduled_scans() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n_over int := 0; n_leads int := 0; n_props int := 0; n_rem int := 0; n_exp int := 0; n_gen int := 0; rec record; today date := app.br_date(now());
begin
  for rec in select t.id, t.agency_id, t.description, t.amount, t.due_date from public.fin_transactions t
              join public.agencies a on a.id = t.agency_id and a.status = 'active'
              where t.direction = 'in' and t.status in ('previsto','emitido') and t.due_date < today loop
    perform app.notify('Pagamento em atraso', rec.description || ' — R$ ' || to_char(rec.amount, 'FM999G999G990D00') || ' (venc. ' || to_char(rec.due_date, 'DD/MM/YYYY') || ')',
                       '/financeiro?tab=receber', 'critical', 'financeiro', null, 'overdue:' || rec.id, rec.agency_id);
    n_over := n_over + 1;
  end loop;

  for rec in select l.id, l.agency_id, l.name, l.owner_id from public.leads l join public.pipeline_stages s on s.id = l.stage_id
              join public.agencies a on a.id = l.agency_id and a.status = 'active'
              where s.kind = 'open' and coalesce(l.last_contact_at, l.created_at) < now() - interval '3 days' loop
    perform app.notify('Oportunidade sem acompanhamento', rec.name || ' está há mais de 3 dias sem contato.', '/crm/' || rec.id, 'warning',
                       case when rec.owner_id is null then 'comercial' end, rec.owner_id,
                       'stale-lead:' || rec.id || ':' || to_char(today, 'IYYY-IW'), rec.agency_id);
    n_leads := n_leads + 1;
  end loop;

  for rec in select p.id, p.agency_id, p.number, p.client_display_name, p.owner_id from public.proposals p
              join public.agencies a on a.id = p.agency_id and a.status = 'active'
              where p.status in ('enviada','visualizada') and p.sent_at < now() - interval '5 days' loop
    perform app.notify('Proposta parada', 'Proposta #' || rec.number || ' (' || rec.client_display_name || ') sem resposta há mais de 5 dias.',
                       '/propostas/' || rec.id, 'warning', case when rec.owner_id is null then 'comercial' end, rec.owner_id,
                       'stale-proposal:' || rec.id || ':' || to_char(today, 'IYYY-IW'), rec.agency_id);
    n_props := n_props + 1;
  end loop;

  for rec in select r.id, r.agency_id, r.title, r.lead_id, coalesce(r.assigned_to, r.created_by) as uid from public.lead_reminders r
              join public.agencies a on a.id = r.agency_id and a.status = 'active'
              where r.done_at is null and r.due_at <= now() loop
    perform app.notify('Lembrete: ' || rec.title, null, '/crm/' || rec.lead_id, 'info', case when rec.uid is null then 'comercial' end, rec.uid, 'reminder:' || rec.id, rec.agency_id);
    n_rem := n_rem + 1;
  end loop;

  update public.proposals set status = 'expirada'
   where status in ('enviada','visualizada','em_negociacao') and valid_until is not null and valid_until < today;
  get diagnostics n_exp = row_count;

  n_gen := public.generate_recurring(today);

  return jsonb_build_object('recurring_generated', n_gen, 'overdue', n_over, 'stale_leads', n_leads, 'stale_proposals', n_props, 'reminders', n_rem, 'expired_proposals', n_exp);
end $$;

-- =====================================================================================================
-- I. Operações de plataforma e de gestão de membros (únicos caminhos para mudar vínculo de agência)
-- =====================================================================================================
-- Cria a agência e vincula o proprietário (usuário já existente, sem agência). Somente administrador da plataforma.
create or replace function public.platform_create_agency(p_name text, p_slug text, p_owner_email text, p_plan text default 'trial') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_owner uuid;
begin
  if not app.is_platform_admin() then raise exception 'Apenas o administrador da plataforma pode criar agências' using errcode = '42501'; end if;
  select id into v_owner from public.profiles where lower(email) = lower(btrim(p_owner_email)) and agency_id is null;
  if v_owner is null then raise exception 'O proprietário precisa já ter conta (convite) e não pertencer a outra agência' using errcode = '23514'; end if;
  insert into public.agencies (name, slug, plan) values (btrim(p_name), lower(btrim(p_slug)), p_plan) returning id into v_id;
  update public.profiles set agency_id = v_id, role = 'admin', active = true where id = v_owner;
  return v_id;
end $$;

create or replace function public.platform_set_agency(p_id uuid, p_plan text, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not app.is_platform_admin() then raise exception 'Apenas o administrador da plataforma pode alterar agências' using errcode = '42501'; end if;
  update public.agencies set plan = coalesce(p_plan, plan), status = coalesce(p_status, status) where id = p_id;
  if not found then raise exception 'Agência não encontrada' using errcode = '23514'; end if;
end $$;

-- Administrador da agência vincula à SUA agência um usuário existente que ainda não pertence a nenhuma. Nunca "rouba" usuário de outra agência.
create or replace function public.agency_add_member(p_email text, p_role text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_agency uuid := app.current_agency_id(); v_count int;
begin
  if not app.has_role('admin') or v_agency is null then raise exception 'Apenas administradores da agência podem adicionar usuários' using errcode = '42501'; end if;
  if p_role not in ('admin','comercial','financeiro','designer','trafego') then raise exception 'Perfil inválido' using errcode = '22023'; end if;
  update public.profiles set agency_id = v_agency, role = p_role, active = true
   where lower(email) = lower(btrim(p_email)) and agency_id is null and not is_platform_admin;
  get diagnostics v_count = row_count;
  return v_count = 1;
end $$;

-- =====================================================================================================
-- J. RLS reescrita: todas as políticas exigem a agência do usuário
-- =====================================================================================================
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

alter table public.plans           enable row level security;
alter table public.agencies        enable row level security;
alter table public.agency_counters enable row level security;   -- sem políticas: só funções definer/serviço

create policy plans_select    on public.plans    for select to authenticated using (true);
create policy agencies_select on public.agencies for select to authenticated using (id = (select app.current_agency_id()) or app.is_platform_admin());
create policy agencies_update on public.agencies for update to authenticated
  using (id = (select app.current_agency_id()) and app.has_role('admin')) with check (id = (select app.current_agency_id()) and app.has_role('admin'));

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or (agency_id = (select app.current_agency_id()) and app.is_staff()));
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated
  using (app.has_role('admin') and agency_id = (select app.current_agency_id())) with check (app.has_role('admin') and agency_id = (select app.current_agency_id()));

create policy audit_select on public.audit_log for select to authenticated using (app.has_role('admin') and agency_id = (select app.current_agency_id()));
create policy jobs_select  on public.jobs      for select to authenticated using (app.has_role('admin') and agency_id = (select app.current_agency_id()));

create policy notif_select on public.notifications for select to authenticated
  using (agency_id = (select app.current_agency_id()) and app.is_staff() and (user_id = auth.uid() or (user_id is null and (audience is null or audience = app.user_role()))));
create policy notif_update on public.notifications for update to authenticated
  using (agency_id = (select app.current_agency_id()) and app.is_staff() and (user_id = auth.uid() or (user_id is null and (audience is null or audience = app.user_role()))))
  with check (agency_id = (select app.current_agency_id()) and app.is_staff());

-- clientes / contatos / serviços contratados
create policy clients_select on public.clients for select to authenticated
  using (agency_id = (select app.current_agency_id()) and (app.is_staff() or id = app.current_client_id()));
create policy clients_write on public.clients for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'))
  with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy contacts_select on public.client_contacts for select to authenticated using (agency_id = (select app.current_agency_id()) and app.is_staff());
create policy contacts_write on public.client_contacts for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'))
  with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy cservices_select on public.client_services for select to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy cservices_write on public.client_services for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro'))
  with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro'));

-- CRM
create policy stages_select on public.pipeline_stages for select to authenticated using (agency_id = (select app.current_agency_id()) and app.is_staff());
create policy stages_write on public.pipeline_stages for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin'));
create policy leads_all on public.leads for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));
create policy interactions_all on public.lead_interactions for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));
create policy reminders_all on public.lead_reminders for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));

-- propostas (financeiro só lê)
create policy proposals_select on public.proposals for select to authenticated using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy proposals_write on public.proposals for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));
create policy pitems_select on public.proposal_items for select to authenticated using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy pitems_write on public.proposal_items for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));
create policy pversions_select on public.proposal_versions for select to authenticated using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy pversions_insert on public.proposal_versions for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));
create policy pevents_select on public.proposal_events for select to authenticated using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy pevents_insert on public.proposal_events for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial'));

-- financeiro
create policy fincat_select on public.fin_categories for select to authenticated using (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro','comercial'));
create policy fincat_write on public.fin_categories for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro'));
create policy finrec_all on public.fin_recurring for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro'));
create policy fintx_all on public.fin_transactions for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin','financeiro'));

-- metas
create policy goals_select on public.goals for select to authenticated using (agency_id = (select app.current_agency_id()) and app.has_role('admin','comercial','financeiro'));
create policy goals_write on public.goals for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.has_role('admin')) with check (agency_id = (select app.current_agency_id()) and app.has_role('admin'));

-- storage privado: comprovantes ficam em <agency_id>/<lançamento>/<arquivo>; a pasta raiz TEM que ser a agência do usuário
do $$ begin
  if to_regclass('storage.buckets') is not null then
    execute 'drop policy if exists "finance receipts read" on storage.objects';
    execute 'drop policy if exists "finance receipts write" on storage.objects';
    execute 'drop policy if exists "finance receipts delete" on storage.objects';
    execute $p$create policy "finance receipts read" on storage.objects for select to authenticated
      using (bucket_id = 'finance-receipts' and app.has_role('admin','financeiro') and (storage.foldername(name))[1] = app.current_agency_id()::text)$p$;
    execute $p$create policy "finance receipts write" on storage.objects for insert to authenticated
      with check (bucket_id = 'finance-receipts' and app.has_role('admin','financeiro') and (storage.foldername(name))[1] = app.current_agency_id()::text)$p$;
    execute $p$create policy "finance receipts delete" on storage.objects for delete to authenticated
      using (bucket_id = 'finance-receipts' and app.has_role('admin','financeiro') and (storage.foldername(name))[1] = app.current_agency_id()::text)$p$;
  end if;
end $$;

-- =====================================================================================================
-- K. Privilégios (mesmo modelo da 0005, agora incluindo objetos novos)
-- =====================================================================================================
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
-- tabelas de plataforma: leitura; alteração só pelas funções definer
revoke all on public.plans, public.agencies, public.agency_counters from authenticated;
grant select on public.plans to authenticated;
grant select on public.agencies to authenticated;
grant update (name, brand) on public.agencies to authenticated;     -- plano/status/slug só via platform_set_agency
revoke all on public.agency_counters from authenticated;

revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
grant execute on function public.proposal_public_open(text), public.proposal_public_accept(text, text, text),
                          public.proposal_public_request_changes(text, text, text) to anon, authenticated;
grant execute on function public.dashboard_metrics(date, date, uuid), public.finance_monthly_series(int), public.crm_conversion(date, date),
                          public.generate_recurring(date), public.activate_proposal(uuid, date), public.proposal_snapshot(uuid, text),
                          public.platform_create_agency(text, text, text, text), public.platform_set_agency(uuid, text, text),
                          public.agency_add_member(text, text) to authenticated;
grant execute on function public.claim_jobs(int), public.finish_job(uuid, text), public.run_scheduled_scans() to service_role;
grant execute on function app.client_ip(), app.br_date(timestamptz), app.norm_email(text), app.norm_phone(text), app.has_role(text[]),
                          app.user_role(), app.current_agency_id(), app.is_platform_admin() to anon;
grant execute on function app.notify(text, text, text, text, text, uuid, text, uuid), app.enqueue_job(text, jsonb, timestamptz, text, uuid) to anon;
