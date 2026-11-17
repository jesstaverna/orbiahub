-- ORBIAHUB — 0008 Papéis e permissões configuráveis por agência (inclui "Gestor/Head")
--
-- * profiles.role continua sendo a CHAVE do papel; o significado vem de public.roles (por agência) → lista de permissões.
-- * Os 6 papéis antigos viram papéis de SISTEMA com exatamente as permissões que já tinham (nenhuma mudança de comportamento);
--   novo papel de sistema: gestor (Head). Papéis "admin" e "cliente" são fixos (evita trancar a agência).
-- * Agências criam papéis próprios e editam as permissões dos demais papéis de sistema.
-- * RLS e funções passam a testar app.can('<permissão>') em vez de app.has_role('admin', ...).
-- * Reversível: supabase/rollback/20261116000008_roles_permissions.down.sql

-- =====================================================================================================
-- A. Catálogo de permissões e tabela de papéis
-- =====================================================================================================
create or replace function app.all_permissions() returns text[] language sql immutable as $$
  select array[
    'app.access',            -- entrar no sistema como equipe (cliente externo não tem)
    'clients.read', 'clients.write',
    'clientservices.read', 'clientservices.write',
    'crm.access',            -- leads, interações e lembretes
    'pipeline.manage',       -- etapas do funil
    'proposals.read', 'proposals.write', 'proposals.discount',
    'finance.access',        -- lançamentos, recorrências, categorias, ativar proposta, comprovantes
    'goals.read', 'goals.manage',
    'audit.read', 'automations.read',
    'settings.manage',       -- usuários, papéis, identidade da agência
    'brand.access', 'ads.access', 'reports.access', 'ai.access'   -- módulos ainda sem tabelas próprias (controlam o menu)
  ]
$$;

create table public.roles (
  agency_id    uuid not null default app.current_agency_id() references public.agencies(id) on delete cascade,
  key          text not null check (key ~ '^[a-z][a-z0-9_]{2,30}$'),
  name         text not null check (btrim(name) <> ''),
  permissions  text[] not null default '{}' check (permissions <@ app.all_permissions()),
  is_system    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (agency_id, key)
);
create trigger trg_roles_touch before update on public.roles for each row execute function app.touch_updated_at();
create trigger trg_01_agency_guard before insert or update on public.roles for each row execute function app.agency_guard();
create trigger trg_roles_audit after insert or update or delete on public.roles for each row execute function app.audit();

-- Papéis de sistema: admin (tudo) e cliente (nada) são imutáveis; os demais têm permissões editáveis mas não podem ser apagados.
create or replace function app.roles_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('authenticated','anon') then new.is_system := false; end if;   -- usuário nunca cria papel de sistema
    return new;
  end if;
  if old.is_system then
    if tg_op = 'DELETE' then raise exception 'Papéis de sistema não podem ser removidos' using errcode = '42501'; end if;
    if new.key is distinct from old.key or new.is_system is distinct from old.is_system then
      raise exception 'Papéis de sistema não podem mudar de chave' using errcode = '42501';
    end if;
    if old.key in ('admin','cliente') and (new.permissions is distinct from old.permissions or new.name is distinct from old.name)
       and current_user in ('authenticated','anon') then
      raise exception 'Os papéis Administrador e Cliente são fixos' using errcode = '42501';
    end if;
  elsif tg_op = 'UPDATE' and (new.key is distinct from old.key or new.is_system is distinct from old.is_system) then
    raise exception 'Chave e tipo do papel não podem ser alterados' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
create trigger trg_02_roles_guard before insert or update or delete on public.roles for each row execute function app.roles_guard();

-- Padrões (editáveis) de cada papel de sistema — equivalem às regras que existiam antes desta migração.
create or replace function app.seed_roles(p_agency uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_all text[] := app.all_permissions();
begin
  insert into public.roles (agency_id, key, name, permissions, is_system) values
    (p_agency, 'admin',      'Administrador',    v_all, true),
    (p_agency, 'gestor',     'Gestor / Head',    array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','goals.read','brand.access','ads.access','reports.access','ai.access'], true),
    (p_agency, 'comercial',  'Comercial',        array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','goals.read','brand.access','reports.access','ai.access'], true),
    (p_agency, 'financeiro', 'Financeiro',       array['app.access','clients.read','clients.write','clientservices.read','clientservices.write','proposals.read','finance.access','goals.read','reports.access','ai.access'], true),
    (p_agency, 'designer',   'Designer',         array['app.access','clients.read','brand.access'], true),
    (p_agency, 'trafego',    'Gestor de Tráfego',array['app.access','clients.read','ads.access','reports.access'], true),
    (p_agency, 'cliente',    'Cliente',          '{}', true)
  on conflict (agency_id, key) do nothing;
end $$;

create or replace function app.agencies_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin perform app.seed_roles(new.id); perform app.seed_agency(new.id); return null; end $$;

-- agências já existentes (instalações anteriores) recebem os papéis ANTES de o vínculo ser exigido
do $$ declare a uuid; begin for a in select id from public.agencies loop perform app.seed_roles(a); end loop; end $$;

-- =====================================================================================================
-- B. Vínculo usuário → papel da própria agência
-- =====================================================================================================
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_fk foreign key (agency_id, role) references public.roles (agency_id, key);
-- (usuários sem agência — recém-cadastrados — não são validados: FK composta ignora agency_id nulo)

-- Permissão do usuário logado (false sem agência ativa / inativo).
create or replace function app.can(p_permission text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p_permission = any (r.permissions)
      from public.profiles pr
      join public.agencies a on a.id = pr.agency_id and a.status = 'active'
      join public.roles r on r.agency_id = pr.agency_id and r.key = pr.role
     where pr.id = auth.uid() and pr.active), false)
$$;

create or replace function app.is_staff() returns boolean language sql stable security definer set search_path = public as $$
  select app.can('app.access')
$$;

-- =====================================================================================================
-- C. Funções que decidiam por papel fixo
-- =====================================================================================================
create or replace function app.guard_profile() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated','anon') then
    if new.agency_id is distinct from old.agency_id or new.is_platform_admin is distinct from old.is_platform_admin then
      raise exception 'Vínculo com a agência e perfil de plataforma só podem ser alterados pela plataforma' using errcode = '42501';
    end if;
    if not app.can('settings.manage') and (new.role is distinct from old.role or new.client_id is distinct from old.client_id
         or new.active is distinct from old.active or new.id is distinct from old.id) then
      raise exception 'Apenas quem gerencia a agência pode alterar papel, vínculo ou status do usuário' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create or replace function app.proposals_before() returns trigger language plpgsql as $$
declare v_gross numeric;
begin
  v_gross := new.subtotal_one_time + new.subtotal_monthly * new.contract_months;

  if tg_op = 'INSERT' or new.discount_value is distinct from old.discount_value then
    if new.discount_value > 0 then
      if current_user in ('authenticated','anon') then
        if not app.can('proposals.discount') then
          raise exception 'Descontos precisam ser autorizados por quem tem a permissão de desconto' using errcode = '42501';
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

create or replace function public.activate_proposal(p_id uuid, p_first_due date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.proposals; v_group uuid := gen_random_uuid(); v_cat_rec uuid; v_cat_one uuid;
        i int; v_each numeric; v_rest numeric; v_months int;
begin
  if not app.can('finance.access') then
    raise exception 'Sem permissão para ativar uma proposta (requer acesso ao financeiro)' using errcode = '42501';
  end if;
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

-- Vincula à SUA agência um usuário existente sem agência, com qualquer papel da agência (exceto o de cliente externo).
create or replace function public.agency_add_member(p_email text, p_role text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_agency uuid := app.current_agency_id(); v_count int;
begin
  if not app.can('settings.manage') or v_agency is null then raise exception 'Sem permissão para adicionar usuários' using errcode = '42501'; end if;
  if p_role = 'cliente' or not exists (select 1 from public.roles where agency_id = v_agency and key = p_role) then
    raise exception 'Perfil inválido' using errcode = '22023';
  end if;
  update public.profiles set agency_id = v_agency, role = p_role, active = true
   where lower(email) = lower(btrim(p_email)) and agency_id is null and not is_platform_admin;
  get diagnostics v_count = row_count;
  return v_count = 1;
end $$;

-- =====================================================================================================
-- D. RLS por permissão (substitui as políticas da 0006)
-- =====================================================================================================
do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;
alter table public.roles enable row level security;

create policy plans_select    on public.plans    for select to authenticated using (true);
create policy agencies_select on public.agencies for select to authenticated using (id = (select app.current_agency_id()) or app.is_platform_admin());
create policy agencies_update on public.agencies for update to authenticated
  using (id = (select app.current_agency_id()) and app.can('settings.manage')) with check (id = (select app.current_agency_id()) and app.can('settings.manage'));

create policy roles_select on public.roles for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('app.access'));
create policy roles_write  on public.roles for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('settings.manage')) with check (agency_id = (select app.current_agency_id()) and app.can('settings.manage'));

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or (agency_id = (select app.current_agency_id()) and app.can('app.access')));
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_update_admin on public.profiles for update to authenticated
  using (app.can('settings.manage') and agency_id = (select app.current_agency_id())) with check (app.can('settings.manage') and agency_id = (select app.current_agency_id()));

create policy audit_select on public.audit_log for select to authenticated using (app.can('audit.read') and agency_id = (select app.current_agency_id()));
create policy jobs_select  on public.jobs      for select to authenticated using (app.can('automations.read') and agency_id = (select app.current_agency_id()));

create policy notif_select on public.notifications for select to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('app.access') and (user_id = auth.uid() or (user_id is null and (audience is null or audience = app.user_role()))));
create policy notif_update on public.notifications for update to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('app.access') and (user_id = auth.uid() or (user_id is null and (audience is null or audience = app.user_role()))))
  with check (agency_id = (select app.current_agency_id()) and app.can('app.access'));

-- clientes / contatos / serviços contratados
create policy clients_select on public.clients for select to authenticated
  using (agency_id = (select app.current_agency_id()) and (app.can('clients.read') or id = app.current_client_id()));
create policy clients_write on public.clients for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('clients.write')) with check (agency_id = (select app.current_agency_id()) and app.can('clients.write'));
create policy contacts_select on public.client_contacts for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('clients.read'));
create policy contacts_write on public.client_contacts for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('clients.write')) with check (agency_id = (select app.current_agency_id()) and app.can('clients.write'));
create policy cservices_select on public.client_services for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('clientservices.read'));
create policy cservices_write on public.client_services for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('clientservices.write')) with check (agency_id = (select app.current_agency_id()) and app.can('clientservices.write'));

-- CRM
create policy stages_select on public.pipeline_stages for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('app.access'));
create policy stages_write on public.pipeline_stages for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('pipeline.manage')) with check (agency_id = (select app.current_agency_id()) and app.can('pipeline.manage'));
create policy leads_all on public.leads for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('crm.access')) with check (agency_id = (select app.current_agency_id()) and app.can('crm.access'));
create policy interactions_all on public.lead_interactions for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('crm.access')) with check (agency_id = (select app.current_agency_id()) and app.can('crm.access'));
create policy reminders_all on public.lead_reminders for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('crm.access')) with check (agency_id = (select app.current_agency_id()) and app.can('crm.access'));

-- propostas
create policy proposals_select on public.proposals for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('proposals.read'));
create policy proposals_write on public.proposals for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('proposals.write')) with check (agency_id = (select app.current_agency_id()) and app.can('proposals.write'));
create policy pitems_select on public.proposal_items for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('proposals.read'));
create policy pitems_write on public.proposal_items for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('proposals.write')) with check (agency_id = (select app.current_agency_id()) and app.can('proposals.write'));
create policy pversions_select on public.proposal_versions for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('proposals.read'));
create policy pversions_insert on public.proposal_versions for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.can('proposals.write'));
create policy pevents_select on public.proposal_events for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('proposals.read'));
create policy pevents_insert on public.proposal_events for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.can('proposals.write'));

-- financeiro (categorias também são lidas por quem monta propostas)
create policy fincat_select on public.fin_categories for select to authenticated
  using (agency_id = (select app.current_agency_id()) and (app.can('finance.access') or app.can('proposals.write')));
create policy fincat_write on public.fin_categories for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('finance.access')) with check (agency_id = (select app.current_agency_id()) and app.can('finance.access'));
create policy finrec_all on public.fin_recurring for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('finance.access')) with check (agency_id = (select app.current_agency_id()) and app.can('finance.access'));
create policy fintx_all on public.fin_transactions for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('finance.access')) with check (agency_id = (select app.current_agency_id()) and app.can('finance.access'));

-- metas
create policy goals_select on public.goals for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('goals.read'));
create policy goals_write on public.goals for all to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('goals.manage')) with check (agency_id = (select app.current_agency_id()) and app.can('goals.manage'));

do $$ begin
  if to_regclass('storage.buckets') is not null then
    execute 'drop policy if exists "finance receipts read" on storage.objects';
    execute 'drop policy if exists "finance receipts write" on storage.objects';
    execute 'drop policy if exists "finance receipts delete" on storage.objects';
    execute $p$create policy "finance receipts read" on storage.objects for select to authenticated
      using (bucket_id = 'finance-receipts' and app.can('finance.access') and (storage.foldername(name))[1] = app.current_agency_id()::text)$p$;
    execute $p$create policy "finance receipts write" on storage.objects for insert to authenticated
      with check (bucket_id = 'finance-receipts' and app.can('finance.access') and (storage.foldername(name))[1] = app.current_agency_id()::text)$p$;
    execute $p$create policy "finance receipts delete" on storage.objects for delete to authenticated
      using (bucket_id = 'finance-receipts' and app.can('finance.access') and (storage.foldername(name))[1] = app.current_agency_id()::text)$p$;
  end if;
end $$;

-- =====================================================================================================
-- E. Privilégios
-- =====================================================================================================
grant select, insert, update, delete on public.roles to authenticated;
grant all on public.roles to service_role;
revoke all on public.roles from anon;
revoke execute on function app.all_permissions(), app.can(text), app.seed_roles(uuid), app.roles_guard() from public, anon;
grant execute on function app.all_permissions(), app.can(text), app.seed_roles(uuid), app.roles_guard() to authenticated, service_role;
grant execute on function public.activate_proposal(uuid, date), public.agency_add_member(text, text) to authenticated;
