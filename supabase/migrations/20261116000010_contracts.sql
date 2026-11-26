-- ORBIAHUB — 0010 Contratos: biblioteca de cláusulas, modelos por tipo de serviço, geração a partir da proposta, revisão humana obrigatória
--
-- ATENÇÃO JURÍDICA: os modelos e cláusulas "starter" são pontos de partida GENÉRICOS e EDITÁVEIS. Não têm validade jurídica automática
-- e DEVEM ser revisados por profissional habilitado. Lacunas ficam como [CAMPO A PREENCHER] e o sistema BLOQUEIA a aprovação enquanto existirem.
-- O sistema NÃO assina nada: "assinado" só é registrado (a) manualmente, com nota de evidência, como "assinado fora do sistema", ou
-- (b) por um provedor de assinatura real (integração futura, via service role). Nenhuma validade legal é presumida.
--
-- * Fluxo: rascunho → em_revisao → aguardando_assinatura → assinado → encerrado   (cancelado a partir de qualquer estado não final)
-- * Conteúdo trava ao entrar em "aguardando_assinatura"; voltar à revisão limpa a aprovação.
-- * Contrato guarda CÓPIA renderizada: alterar modelo/cláusula depois não muda contratos existentes.
-- * Reversível: supabase/rollback/20261116000010_contracts.down.sql (APAGA contratos, modelos e cláusulas)

-- =====================================================================================================
-- A. Permissões
-- =====================================================================================================
create or replace function app.all_permissions() returns text[] language sql immutable as $$
  select array[
    'app.access',
    'clients.read', 'clients.write',
    'clientservices.read', 'clientservices.write',
    'crm.access',
    'pipeline.manage',
    'proposals.read', 'proposals.write', 'proposals.discount',
    'catalog.read', 'catalog.manage',
    'contracts.read', 'contracts.write',
    'contracts.approve',     -- aprovar após revisão, enviar para assinatura, registrar assinatura
    'contracts.templates',   -- gerenciar modelos e biblioteca de cláusulas
    'finance.access',
    'goals.read', 'goals.manage',
    'audit.read', 'automations.read',
    'settings.manage',
    'brand.access', 'ads.access', 'reports.access', 'ai.access'
  ]
$$;

create or replace function app.seed_roles(p_agency uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_all text[] := app.all_permissions();
begin
  insert into public.roles (agency_id, key, name, permissions, is_system) values
    (p_agency, 'admin',      'Administrador',    v_all, true),
    (p_agency, 'gestor',     'Gestor / Head',    array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','catalog.read','catalog.manage','contracts.read','contracts.write','contracts.approve','contracts.templates','goals.read','brand.access','ads.access','reports.access','ai.access'], true),
    (p_agency, 'comercial',  'Comercial',        array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','catalog.read','contracts.read','contracts.write','goals.read','brand.access','reports.access','ai.access'], true),
    (p_agency, 'financeiro', 'Financeiro',       array['app.access','clients.read','clients.write','clientservices.read','clientservices.write','proposals.read','catalog.read','contracts.read','finance.access','goals.read','reports.access','ai.access'], true),
    (p_agency, 'designer',   'Designer',         array['app.access','clients.read','brand.access'], true),
    (p_agency, 'trafego',    'Gestor de Tráfego',array['app.access','clients.read','ads.access','reports.access'], true),
    (p_agency, 'cliente',    'Cliente',          '{}', true)
  on conflict (agency_id, key) do nothing;
end $$;

update public.roles r set permissions = (select array_agg(distinct x) from unnest(r.permissions || p.add) x)
  from (values ('admin',      array['contracts.read','contracts.write','contracts.approve','contracts.templates']),
               ('gestor',     array['contracts.read','contracts.write','contracts.approve','contracts.templates']),
               ('comercial',  array['contracts.read','contracts.write']),
               ('financeiro', array['contracts.read'])) as p(key, add)
 where r.is_system and r.key = p.key;

-- =====================================================================================================
-- B. Tabelas
-- =====================================================================================================
create table public.clause_library (
  id          uuid primary key default gen_random_uuid(),
  agency_id   uuid not null default app.current_agency_id() references public.agencies(id) on delete restrict,
  title       text not null check (btrim(title) <> ''),
  category    text not null default 'geral'
              check (category in ('partes','escopo','prazos','obrigacoes','revisoes','pagamento','propriedade','ia','confidencialidade','vigencia','responsabilidade','foro','servico','geral')),
  body        text not null check (btrim(body) <> ''),     -- aceita variáveis {{cliente.nome}} etc.
  is_starter  boolean not null default false,              -- veio do modelo-base (ainda exige revisão jurídica)
  active      boolean not null default true,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index clause_library_title_uidx on public.clause_library (agency_id, lower(title));
create index clause_library_agency_idx on public.clause_library (agency_id, active);

create table public.contract_templates (
  id           uuid primary key default gen_random_uuid(),
  agency_id    uuid not null default app.current_agency_id() references public.agencies(id) on delete restrict,
  name         text not null check (btrim(name) <> ''),
  service_type text not null default 'geral'
               check (service_type in ('social_media','trafego_pago','branding','site','landing_page','design','consultoria','geral')),
  description  text,
  is_starter   boolean not null default false,
  active       boolean not null default true,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index contract_templates_name_uidx on public.contract_templates (agency_id, lower(name));
create index contract_templates_agency_idx on public.contract_templates (agency_id, active);

create table public.contract_template_clauses (
  id          uuid primary key default gen_random_uuid(),
  agency_id   uuid not null references public.agencies(id) on delete restrict,    -- herdado do modelo (trigger)
  template_id uuid not null references public.contract_templates(id) on delete cascade,
  clause_id   uuid not null references public.clause_library(id) on delete restrict,
  position    int  not null default 0,
  unique (template_id, clause_id)
);
create index contract_template_clauses_idx on public.contract_template_clauses (template_id, position);
create index contract_template_clauses_agency_idx on public.contract_template_clauses (agency_id);

create table public.contracts (
  id                    uuid primary key default gen_random_uuid(),
  agency_id             uuid not null default app.current_agency_id() references public.agencies(id) on delete restrict,
  number                int  not null,                                  -- sequencial por agência (trigger)
  title                 text not null check (btrim(title) <> ''),
  status                text not null default 'rascunho'
                        check (status in ('rascunho','em_revisao','aguardando_assinatura','assinado','encerrado','cancelado')),
  contract_type         text not null default 'pontual' check (contract_type in ('recorrente','pontual')),
  proposal_id           uuid references public.proposals(id) on delete set null,
  client_id             uuid not null references public.clients(id) on delete restrict,
  template_id           uuid references public.contract_templates(id) on delete set null,
  content               jsonb not null default '[]'::jsonb,              -- [{ "title": "...", "body": "..." }] — cópia renderizada
  variables             jsonb not null default '{}'::jsonb,              -- variáveis usadas na geração (referência)
  start_date            date,
  end_date              date,
  auto_renew            boolean not null default false,
  renewal_notice_days   int  not null default 30 check (renewal_notice_days between 0 and 365),
  monthly_value         numeric(14,2) not null default 0 check (monthly_value >= 0),
  one_time_value        numeric(14,2) not null default 0 check (one_time_value >= 0),
  total_value           numeric(14,2) not null default 0 check (total_value >= 0),
  payment_terms         text not null default '',
  version               int  not null default 1,
  review_confirmed      boolean not null default false,                  -- "revisado por quem de direito" (humano, obrigatório)
  reviewed_by           uuid references public.profiles(id),
  reviewed_at           timestamptz,
  signed_at             timestamptz,
  signature_method      text check (signature_method in ('manual','provider')),   -- manual = FORA do sistema; provider = integração real
  signature_provider    text,
  signature_ref         jsonb not null default '{}'::jsonb,              -- id/status do documento no provedor (integração futura)
  signature_note        text,                                            -- evidência do registro manual
  cancelled_reason      text,
  owner_id              uuid references public.profiles(id) on delete set null,
  created_by            uuid references public.profiles(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  unique (agency_id, number)
);
create unique index contracts_proposal_uidx on public.contracts (proposal_id) where proposal_id is not null and status <> 'cancelado';
create index contracts_agency_status_idx on public.contracts (agency_id, status);
create index contracts_client_idx on public.contracts (client_id);
create index contracts_end_idx on public.contracts (end_date) where status = 'assinado';

create table public.contract_versions (
  id          uuid primary key default gen_random_uuid(),
  agency_id   uuid not null references public.agencies(id) on delete restrict,
  contract_id uuid not null references public.contracts(id) on delete cascade,
  version     int  not null,
  snapshot    jsonb not null,
  note        text,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  unique (contract_id, version)
);
create index contract_versions_agency_idx on public.contract_versions (agency_id);

create table public.contract_events (
  id          uuid primary key default gen_random_uuid(),
  agency_id   uuid not null references public.agencies(id) on delete restrict,
  contract_id uuid not null references public.contracts(id) on delete cascade,
  kind        text not null check (kind in ('criado','rascunho','em_revisao','aguardando_assinatura','assinado','encerrado','cancelado','renovado','versao','nota')),
  message     text,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);
create index contract_events_idx on public.contract_events (contract_id, created_at desc);
create index contract_events_agency_idx on public.contract_events (agency_id);

-- triggers genéricos (integridade entre agências, auditoria, updated_at)
create trigger trg_clause_library_touch before update on public.clause_library for each row execute function app.touch_updated_at();
create trigger trg_contract_templates_touch before update on public.contract_templates for each row execute function app.touch_updated_at();
create trigger trg_contracts_touch before update on public.contracts for each row execute function app.touch_updated_at();
create trigger trg_clause_library_audit after insert or update or delete on public.clause_library for each row execute function app.audit();
create trigger trg_contract_templates_audit after insert or update or delete on public.contract_templates for each row execute function app.audit();
create trigger trg_contract_tpl_clauses_audit after insert or update or delete on public.contract_template_clauses for each row execute function app.audit();
create trigger trg_contracts_audit after insert or update or delete on public.contracts for each row execute function app.audit();
create trigger trg_01_agency_guard before insert or update on public.clause_library for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.contract_templates for each row execute function app.agency_guard();
create trigger trg_00_agency_inherit before insert on public.contract_template_clauses for each row execute function app.agency_inherit('template_id', 'contract_templates');
create trigger trg_01_agency_guard before insert or update on public.contract_template_clauses for each row execute function app.agency_guard('clause_id:clause_library');
create trigger trg_01_agency_guard before insert or update on public.contracts for each row execute function app.agency_guard('client_id:clients', 'proposal_id:proposals', 'template_id:contract_templates', 'owner_id:profiles', 'reviewed_by:profiles');
create trigger trg_00_agency_inherit before insert on public.contract_versions for each row execute function app.agency_inherit('contract_id', 'contracts');
create trigger trg_01_agency_guard before insert or update on public.contract_versions for each row execute function app.agency_guard();
create trigger trg_00_agency_inherit before insert on public.contract_events for each row execute function app.agency_inherit('contract_id', 'contracts');
create trigger trg_01_agency_guard before insert or update on public.contract_events for each row execute function app.agency_guard();

-- número do contrato: sequencial por agência
create or replace function app.contracts_number() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.number is null then new.number := app.next_counter(new.agency_id, 'contract'); end if;
  return new;
end $$;
create trigger trg_00_contracts_number before insert on public.contracts for each row execute function app.contracts_number();

-- =====================================================================================================
-- C. Regras do ciclo de vida (no banco: valem para UI, API, worker e IA)
-- =====================================================================================================
create or replace function app.contracts_before() returns trigger language plpgsql as $$
declare
  v_user boolean := current_user in ('authenticated','anon');
  v_allowed text[] := array['rascunho>em_revisao','em_revisao>rascunho','em_revisao>aguardando_assinatura','aguardando_assinatura>em_revisao',
                            'aguardando_assinatura>assinado','assinado>encerrado','rascunho>cancelado','em_revisao>cancelado',
                            'aguardando_assinatura>cancelado','assinado>cancelado'];
  v_txt text;
begin
  if tg_op = 'INSERT' then
    if v_user then
      if new.status <> 'rascunho' then raise exception 'Contratos nascem como rascunho' using errcode = '23514'; end if;
      new.review_confirmed := false; new.reviewed_by := null; new.reviewed_at := null;
      new.signed_at := null; new.signature_method := null; new.signature_provider := null; new.signature_ref := '{}'::jsonb; new.signature_note := null;
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    if v_user then
      if old.status not in ('rascunho','em_revisao') and (
           new.content is distinct from old.content or new.variables is distinct from old.variables or new.title is distinct from old.title
        or new.start_date is distinct from old.start_date or new.end_date is distinct from old.end_date
        or new.monthly_value is distinct from old.monthly_value or new.one_time_value is distinct from old.one_time_value or new.total_value is distinct from old.total_value
        or new.payment_terms is distinct from old.payment_terms or new.client_id is distinct from old.client_id
        or new.proposal_id is distinct from old.proposal_id or new.contract_type is distinct from old.contract_type) then
        raise exception 'Contrato em "%" não pode ser editado. Volte para revisão ou registre um aditivo.', old.status using errcode = '23514';
      end if;
      if new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.review_confirmed is distinct from old.review_confirmed
         or new.signed_at is distinct from old.signed_at or new.signature_method is distinct from old.signature_method
         or new.signature_provider is distinct from old.signature_provider or new.signature_ref is distinct from old.signature_ref then
        raise exception 'Revisão e assinatura só mudam por transição de status' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  -- mudança de status
  if v_user and not (old.status || '>' || new.status = any (v_allowed)) then
    raise exception 'Transição inválida: % → %', old.status, new.status using errcode = '23514';
  end if;

  if new.status in ('rascunho','em_revisao') then              -- voltou para edição: aprovação anterior deixa de valer
    new.review_confirmed := false; new.reviewed_by := null; new.reviewed_at := null;
  end if;

  if new.status = 'aguardando_assinatura' then
    if v_user and not app.can('contracts.approve') then raise exception 'Sem permissão para aprovar contratos' using errcode = '42501'; end if;
    if not new.review_confirmed then raise exception 'Confirme a revisão do contrato antes de enviar para assinatura' using errcode = '23514'; end if;
    v_txt := new.content::text;
    if v_txt like '%{{%' or v_txt like '%[CAMPO A PREENCHER%' then
      raise exception 'Há variáveis ou [CAMPO A PREENCHER] sem resolver. Preencha todas as lacunas antes de aprovar.' using errcode = '23514';
    end if;
    if new.start_date is null then raise exception 'Informe a data de início do contrato' using errcode = '23514'; end if;
    new.reviewed_by := coalesce(auth.uid(), new.reviewed_by); new.reviewed_at := now();
  end if;

  if new.status = 'assinado' then
    if v_user then
      if not app.can('contracts.approve') then raise exception 'Sem permissão para registrar a assinatura' using errcode = '42501'; end if;
      if length(btrim(coalesce(new.signature_note, ''))) < 5 then
        raise exception 'Descreva a evidência da assinatura (como e onde foi assinado, por quem)' using errcode = '23514';
      end if;
      if new.signature_method = 'provider' or new.signature_provider is distinct from old.signature_provider or new.signature_ref is distinct from old.signature_ref then
        raise exception 'Somente um provedor de assinatura integrado registra assinatura eletrônica' using errcode = '42501';
      end if;
      new.signature_method := 'manual';       -- fora do sistema; só um provedor real (service role) registra "provider"
    elsif new.signature_method is null then
      raise exception 'Registro de assinatura sem método' using errcode = '23514';
    end if;
    new.signed_at := coalesce(new.signed_at, now());
  end if;

  if new.status = 'cancelado' and length(btrim(coalesce(new.cancelled_reason, ''))) < 3 then
    raise exception 'Informe o motivo do cancelamento' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_02_contracts_before before insert or update on public.contracts for each row execute function app.contracts_before();

create or replace function app.contracts_after() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into public.contract_events (contract_id, kind, message, created_by) values (new.id, new.status, old.status || ' → ' || new.status, auth.uid());
    if new.status = 'em_revisao' then
      perform app.notify('Contrato #' || new.number || ' aguarda revisão', new.title, '/contratos/' || new.id, 'info', 'admin', null,
                         'contract.review:' || new.id || ':' || extract(epoch from now())::bigint, new.agency_id);
    end if;
    if new.status = 'assinado' then
      perform app.enqueue_job('contract.signed', jsonb_build_object('contract_id', new.id), now(), 'contract.signed:' || new.id, new.agency_id);
      perform app.notify('Contrato #' || new.number || ' assinado', new.title || ' — inicie o onboarding e os projetos do cliente.', '/contratos/' || new.id, 'info', 'admin', null,
                         'contract.signed:' || new.id, new.agency_id);
    end if;
  end if;
  return null;
end $$;
create trigger trg_contracts_after after update on public.contracts for each row execute function app.contracts_after();

-- =====================================================================================================
-- D. Renderização e geração
-- =====================================================================================================
create or replace function app.fmt_brl(n numeric) returns text language sql immutable as $$
  select 'R$ ' || translate(to_char(coalesce(n, 0), 'FM999,999,999,990.00'), ',.', '.,')
$$;
create or replace function app.fmt_date(d date) returns text language sql immutable as $$
  select case when d is null then null else to_char(d, 'DD/MM/YYYY') end
$$;
-- troca {{chave}} pelos valores; chaves desconhecidas permanecem visíveis (e bloqueiam a aprovação)
create or replace function app.render_vars(p_text text, p_vars jsonb) returns text language plpgsql immutable as $$
declare r record; v text := coalesce(p_text, '');
begin
  for r in select key, value from jsonb_each_text(p_vars) loop v := replace(v, '{{' || r.key || '}}', r.value); end loop;
  return v;
end $$;

-- Gera um RASCUNHO a partir de um modelo (e, opcionalmente, de uma proposta aceita). SECURITY INVOKER: respeita a RLS de quem chama.
create or replace function public.contract_generate(p_template uuid, p_proposal uuid default null, p_client uuid default null, p_start date default null, p_title text default null)
returns uuid language plpgsql security invoker as $$
declare
  t public.contract_templates; p public.proposals; c public.clients; ag public.agencies; k public.contracts;
  v_blank constant text := '[CAMPO A PREENCHER]';
  v_start date := coalesce(p_start, app.br_date(now())); v_months int; v_type text; v_end date;
  v_mon numeric := 0; v_one numeric := 0; v_tot numeric := 0; v_terms text := ''; v_services text; v_vars jsonb; v_content jsonb; v_id uuid;
begin
  select * into t from public.contract_templates where id = p_template and active;
  if not found then raise exception 'Modelo inexistente ou inativo' using errcode = '23514'; end if;

  if p_proposal is not null then
    select * into p from public.proposals where id = p_proposal;
    if not found then raise exception 'Proposta não encontrada'; end if;
    if p.status <> 'aceita' then raise exception 'Somente propostas aceitas geram contrato' using errcode = '23514'; end if;
    if p.client_id is null then raise exception 'A proposta ainda não tem cliente vinculado' using errcode = '23514'; end if;
    p_client := p.client_id;
  end if;
  if p_client is null then raise exception 'Informe o cliente' using errcode = '22023'; end if;
  select * into c from public.clients where id = p_client;
  if not found then raise exception 'Cliente não encontrado'; end if;
  select * into ag from public.agencies where id = c.agency_id;

  if p_proposal is not null then
    v_months := p.contract_months;
    v_mon := p.subtotal_monthly; v_one := greatest(p.subtotal_one_time - p.discount_value, 0); v_tot := p.total_value; v_terms := p.payment_terms;
    v_type := case when p.subtotal_monthly > 0 then 'recorrente' else 'pontual' end;
    select string_agg(E'• ' || i.description || ' — ' || case i.billing when 'mensal' then 'mensal' else 'pontual' end || ' — '
                      || regexp_replace(i.quantity::text, '\.?0+$', '') || ' × ' || app.fmt_brl(i.unit_price)
                      || coalesce(E'\n   ' || replace(i.details, E'\n', E'\n   '), ''), E'\n' order by i.position)
      into v_services from public.proposal_items i where i.proposal_id = p.id;
  else
    v_type := 'pontual'; v_months := null;
  end if;
  v_end := case when v_type = 'recorrente' and v_months is not null then (v_start + (v_months || ' months')::interval)::date - 1 end;

  insert into public.contracts (agency_id, title, contract_type, proposal_id, client_id, template_id, start_date, end_date, monthly_value, one_time_value, total_value, payment_terms, owner_id, created_by)
  values (c.agency_id, coalesce(nullif(btrim(p_title), ''), 'Contrato de prestação de serviços — ' || c.name), v_type, p_proposal, c.id, t.id, v_start, v_end, v_mon, v_one, v_tot, coalesce(v_terms, ''), auth.uid(), auth.uid())
  returning * into k;

  v_vars := jsonb_build_object(
    'cliente.nome',          coalesce(nullif(btrim(c.name), ''), v_blank),
    'cliente.razao_social',  coalesce(nullif(btrim(c.legal_name), ''), nullif(btrim(c.name), ''), v_blank),
    'cliente.documento',     coalesce(nullif(btrim(c.document), ''), v_blank),
    'cliente.endereco',      coalesce(nullif(btrim(c.address), ''), v_blank),
    'cliente.email',         coalesce(nullif(btrim(c.email), ''), v_blank),
    'cliente.telefone',      coalesce(nullif(btrim(c.phone), ''), v_blank),
    'agencia.nome',          ag.name,
    'contrato.numero',       k.number::text,
    'contrato.titulo',       k.title,
    'contrato.tipo',         case k.contract_type when 'recorrente' then 'prestação continuada (mensal)' else 'projeto pontual' end,
    'contrato.inicio',       app.fmt_date(k.start_date),
    'contrato.fim',          coalesce(app.fmt_date(k.end_date), 'a conclusão das entregas e a quitação dos valores'),
    'contrato.vigencia_meses', coalesce(v_months::text, 'prazo do projeto'),
    'contrato.valor_mensal', app.fmt_brl(k.monthly_value),
    'contrato.valor_pontual', app.fmt_brl(k.one_time_value),
    'contrato.valor_total',  app.fmt_brl(k.total_value),
    'contrato.forma_pagamento', coalesce(nullif(btrim(k.payment_terms), ''), v_blank),
    'contrato.parcelas',     coalesce(p.installments::text, '1'),
    'contrato.aviso_renovacao_dias', k.renewal_notice_days::text,
    'proposta.numero',       coalesce(p.number::text, '—'),
    'servicos.lista',        coalesce(v_services, '[CAMPO A PREENCHER — descrever serviços e entregáveis]'),
    'data.hoje',             app.fmt_date(app.br_date(now())));

  select coalesce(jsonb_agg(jsonb_build_object('title', cl.title, 'body', app.render_vars(cl.body, v_vars)) order by tc.position), '[]'::jsonb)
    into v_content
    from public.contract_template_clauses tc join public.clause_library cl on cl.id = tc.clause_id
   where tc.template_id = t.id and cl.active;
  if v_content = '[]'::jsonb then raise exception 'O modelo não tem cláusulas ativas' using errcode = '23514'; end if;

  update public.contracts set content = v_content, variables = v_vars where id = k.id;
  insert into public.contract_versions (contract_id, version, snapshot, note, created_by)
    select k.id, 1, to_jsonb(x), 'Versão inicial gerada do modelo "' || t.name || '"', auth.uid() from public.contracts x where x.id = k.id;
  insert into public.contract_events (contract_id, kind, message, created_by)
  values (k.id, 'criado', 'Gerado do modelo "' || t.name || '"' || coalesce(' e da proposta #' || p.number, ''), auth.uid());
  return k.id;
end $$;

-- Versão imutável (snapshot) sob demanda
create or replace function public.contract_snapshot(p_id uuid, p_note text default null) returns int
language plpgsql security invoker as $$
declare v_next int; v_snap jsonb;
begin
  select to_jsonb(c) into v_snap from public.contracts c where c.id = p_id;
  if v_snap is null then raise exception 'Contrato não encontrado'; end if;
  select coalesce(max(version), 0) + 1 into v_next from public.contract_versions where contract_id = p_id;
  insert into public.contract_versions (contract_id, version, snapshot, note, created_by) values (p_id, v_next, v_snap, p_note, auth.uid());
  update public.contracts set version = v_next where id = p_id;
  return v_next;
end $$;

-- Renovação: prorroga a vigência de um contrato JÁ ASSINADO (decisão humana, registrada). Não presume renovação automática.
create or replace function public.contract_renew(p_id uuid, p_months int) returns date
language plpgsql security definer set search_path = public as $$
declare k public.contracts; v_new date;
begin
  if not app.can('contracts.write') then raise exception 'Sem permissão para renovar contratos' using errcode = '42501'; end if;
  if p_months is null or p_months < 1 or p_months > 60 then raise exception 'Informe de 1 a 60 meses' using errcode = '22023'; end if;
  select * into k from public.contracts where id = p_id and agency_id = app.current_agency_id() for update;
  if not found then raise exception 'Contrato não encontrado'; end if;
  if k.status <> 'assinado' or k.end_date is null then raise exception 'Só contratos assinados e com vigência definida podem ser renovados' using errcode = '23514'; end if;
  v_new := (k.end_date + (p_months || ' months')::interval)::date;
  update public.contracts set end_date = v_new where id = k.id;
  insert into public.contract_events (contract_id, kind, message, created_by) values (k.id, 'renovado', 'Vigência prorrogada em ' || p_months || ' mês(es): ' || app.fmt_date(k.end_date) || ' → ' || app.fmt_date(v_new), auth.uid());
  insert into public.contract_versions (contract_id, version, snapshot, note, created_by)
    select k.id, coalesce(max(version), 0) + 1, (select to_jsonb(c) from public.contracts c where c.id = k.id), 'Renovação de ' || p_months || ' mês(es)', auth.uid() from public.contract_versions where contract_id = k.id;
  update public.contracts set version = (select max(version) from public.contract_versions where contract_id = k.id) where id = k.id;
  return v_new;
end $$;

-- Varredura do worker: vencimentos e renovações (todas as agências ativas; sempre no escopo da agência do contrato)
create or replace function public.run_contract_scans() returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec record; today date := app.br_date(now()); n_soon int := 0; n_over int := 0;
begin
  for rec in select c.id, c.agency_id, c.number, c.end_date, c.owner_id, c.auto_renew from public.contracts c
              join public.agencies a on a.id = c.agency_id and a.status = 'active'
             where c.status = 'assinado' and c.end_date is not null and c.end_date >= today and c.end_date - today <= c.renewal_notice_days loop
    perform app.notify('Contrato #' || rec.number || ' vence em ' || (rec.end_date - today) || ' dia(s)',
                       case when rec.auto_renew then 'Renovação prevista: confirme as condições com o cliente.' else 'Defina a renovação ou o encerramento.' end,
                       '/contratos/' || rec.id, 'warning', case when rec.owner_id is null then 'admin' end, rec.owner_id,
                       'contract-expiring:' || rec.id || ':' || rec.end_date, rec.agency_id);
    n_soon := n_soon + 1;
  end loop;
  for rec in select c.id, c.agency_id, c.number, c.end_date, c.owner_id from public.contracts c
              join public.agencies a on a.id = c.agency_id and a.status = 'active'
             where c.status = 'assinado' and c.end_date is not null and c.end_date < today loop
    perform app.notify('Contrato #' || rec.number || ' com vigência encerrada', 'A vigência terminou em ' || app.fmt_date(rec.end_date) || '. Renove ou encerre o contrato.',
                       '/contratos/' || rec.id, 'critical', case when rec.owner_id is null then 'admin' end, rec.owner_id,
                       'contract-expired:' || rec.id || ':' || rec.end_date, rec.agency_id);
    n_over := n_over + 1;
  end loop;
  return jsonb_build_object('expiring', n_soon, 'expired', n_over);
end $$;

-- =====================================================================================================
-- E. Modelos-base (starter) — estrutura da skill de contratos da Guria; TEXTO GENÉRICO, SEMPRE SUJEITO A REVISÃO JURÍDICA
-- =====================================================================================================
create or replace function app.seed_contracts(p_agency uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  before_svc text[] := array['Partes e definições','Objeto e escopo','Entregáveis e cronograma','Obrigações da contratante','Obrigações da contratada'];
  after_svc  text[] := array['Revisões e alterações de escopo','Valor e forma de pagamento','Propriedade intelectual','Uso de inteligência artificial','Confidencialidade e proteção de dados','Vigência e renovação','Rescisão','Limitação de responsabilidade','Foro e assinatura'];
  t record; titles text[]; i int; tid uuid;
begin
  if exists (select 1 from public.clause_library where agency_id = p_agency and is_starter) then return; end if;

  insert into public.clause_library (agency_id, title, category, body, is_starter) values
  (p_agency, 'Partes e definições', 'partes', $b$CONTRATADA: {{agencia.nome}}, [CAMPO A PREENCHER — CNPJ/CPF e endereço da contratada].
CONTRATANTE: {{cliente.razao_social}}, documento nº {{cliente.documento}}, com endereço em {{cliente.endereco}}, e-mail {{cliente.email}}.
As partes firmam este contrato nº {{contrato.numero}} ({{contrato.tipo}}), vinculado à proposta comercial nº {{proposta.numero}}, que passa a integrá-lo.$b$, true),
  (p_agency, 'Objeto e escopo', 'escopo', $b$O objeto deste contrato é a prestação dos serviços descritos abaixo, nos limites da proposta nº {{proposta.numero}}:

{{servicos.lista}}

Não estão incluídos no escopo: [CAMPO A PREENCHER — listar as exclusões]. Qualquer demanda fora deste escopo será orçada à parte e só será executada após aprovação por escrito.$b$, true),
  (p_agency, 'Entregáveis e cronograma', 'prazos', $b$Os entregáveis são os descritos na cláusula de Objeto e escopo. Prazos de entrega: [CAMPO A PREENCHER — datas ou prazos em dias úteis, por entregável]. Os prazos dependem do envio dos materiais e das aprovações da CONTRATANTE nos prazos previstos na cláusula de Obrigações da contratante.$b$, true),
  (p_agency, 'Obrigações da contratante', 'obrigacoes', $b$A CONTRATANTE se obriga a: (a) fornecer briefing completo e os materiais necessários (logotipos, textos, imagens, acessos) em até [CAMPO A PREENCHER] dias úteis após a assinatura; (b) aprovar ou solicitar ajustes em cada entrega em até [CAMPO A PREENCHER] dias úteis, sendo que a ausência de resposta nesse prazo suspende os prazos da CONTRATADA; (c) efetuar os pagamentos nas datas combinadas; (d) responder pela veracidade e pela licitude das informações e dos materiais que fornecer.$b$, true),
  (p_agency, 'Obrigações da contratada', 'obrigacoes', $b$A CONTRATADA se obriga a: (a) executar os serviços com diligência e técnica adequadas; (b) comunicar à CONTRATANTE, com antecedência, qualquer impedimento que afete os prazos; (c) entregar os trabalhos nos formatos combinados; (d) manter a CONTRATANTE informada sobre o andamento.$b$, true),
  (p_agency, 'Revisões e alterações de escopo', 'revisoes', $b$Estão incluídas [CAMPO A PREENCHER] rodadas de revisão por entregável. Revisões adicionais e mudanças de escopo serão orçadas e dependem de aprovação por escrito da CONTRATANTE antes da execução. Solicitações devem ser feitas por [CAMPO A PREENCHER — canal formal, ex.: e-mail].$b$, true),
  (p_agency, 'Valor e forma de pagamento', 'pagamento', $b$Valor mensal: {{contrato.valor_mensal}}. Valor pontual: {{contrato.valor_pontual}}. Valor total do contrato: {{contrato.valor_total}}.
Condições de pagamento: {{contrato.forma_pagamento}} (número de parcelas do valor pontual: {{contrato.parcelas}}).
Em caso de atraso, incidirão multa de [CAMPO A PREENCHER]% e juros de [CAMPO A PREENCHER]% ao mês sobre o valor em atraso. Reajuste (contratos recorrentes): [CAMPO A PREENCHER — índice e periodicidade, ou "não há reajuste"].$b$, true),
  (p_agency, 'Propriedade intelectual', 'propriedade', $b$Os direitos patrimoniais sobre as criações entregues são cedidos à CONTRATANTE somente após o pagamento integral dos valores correspondentes. A CONTRATADA poderá citar o trabalho em seu portfólio, salvo [CAMPO A PREENCHER — hipótese de sigilo]. Fontes tipográficas, imagens, músicas e demais materiais de terceiros são licenciados por conta de [CAMPO A PREENCHER — CONTRATANTE ou CONTRATADA].$b$, true),
  (p_agency, 'Uso de inteligência artificial', 'ia', $b$A CONTRATADA poderá utilizar ferramentas de inteligência artificial como apoio à pesquisa, criação e produção, sempre com revisão humana. Quando houver criação substancialmente assistida por IA, a CONTRATADA informará a CONTRATANTE. A CONTRATANTE reconhece que a proteção autoral de conteúdo gerado com apoio de IA pode ser limitada ou incerta conforme a legislação aplicável. [CAMPO A PREENCHER — confirmar o tratamento desta cláusula com assessoria jurídica].$b$, true),
  (p_agency, 'Confidencialidade e proteção de dados', 'confidencialidade', $b$As partes manterão sigilo sobre as informações confidenciais a que tiverem acesso em razão deste contrato, durante a vigência e por [CAMPO A PREENCHER] anos após seu término. O tratamento de dados pessoais observará a Lei nº 13.709/2018 (LGPD): os dados serão tratados apenas para a execução deste contrato; cada parte responde pela base legal dos dados que fornecer; incidentes de segurança que envolvam dados pessoais serão comunicados à outra parte em prazo razoável.$b$, true),
  (p_agency, 'Vigência e renovação', 'vigencia', $b$Início da vigência: {{contrato.inicio}}. Término: {{contrato.fim}}. Renovação: [CAMPO A PREENCHER — automática ou mediante aceite expresso], com aviso de {{contrato.aviso_renovacao_dias}} dias antes do término da vigência.$b$, true),
  (p_agency, 'Rescisão', 'vigencia', $b$Qualquer das partes poderá rescindir este contrato mediante aviso prévio por escrito de [CAMPO A PREENCHER] dias. Em caso de rescisão antecipada pela CONTRATANTE, será devida multa de [CAMPO A PREENCHER]. Os serviços executados até a data da rescisão são devidos proporcionalmente; valores pagos por serviços não iniciados serão devolvidos de forma proporcional. O descumprimento de obrigação contratual autoriza a rescisão após notificação e prazo de [CAMPO A PREENCHER] dias para sanar.$b$, true),
  (p_agency, 'Limitação de responsabilidade', 'responsabilidade', $b$A CONTRATADA não garante resultados de vendas, de captação de clientes, de posicionamento em buscadores ou de desempenho de anúncios, que dependem de fatores externos ao seu controle. A responsabilidade da CONTRATADA fica limitada a [CAMPO A PREENCHER — critério, ex.: valor pago nos últimos meses], salvo dolo ou o que a lei não permitir limitar.$b$, true),
  (p_agency, 'Foro e assinatura', 'foro', $b$Fica eleito o foro da comarca de [CAMPO A PREENCHER], com renúncia a qualquer outro. A forma de assinatura (eletrônica ou física, com testemunhas quando aplicável) é [CAMPO A PREENCHER]. Data de emissão: {{data.hoje}}.$b$, true),
  (p_agency, 'Social media — condições', 'servico', $b$As publicações seguirão o calendário editorial aprovado pela CONTRATANTE. O acesso às contas das redes sociais será concedido pela CONTRATANTE por meios seguros, mantendo-se a titularidade das contas com ela. A CONTRATANTE responde pelos direitos de imagem e de uso dos materiais que fornecer. Não há garantia de alcance, engajamento ou número de seguidores. Atendimento de mensagens e comentários: [CAMPO A PREENCHER — incluído ou não incluído].$b$, true),
  (p_agency, 'Tráfego pago — condições', 'servico', $b$A verba de mídia é paga diretamente pela CONTRATANTE às plataformas de anúncio e é independente da remuneração da CONTRATADA. As contas de anúncio permanecem em nome da CONTRATANTE. A CONTRATADA não garante número de leads, vendas ou retorno sobre o investimento. A CONTRATANTE reconhece que as plataformas podem reprovar anúncios ou suspender contas conforme suas políticas. Relatórios serão entregues com periodicidade [CAMPO A PREENCHER].$b$, true),
  (p_agency, 'Branding — condições', 'servico', $b$O projeto seguirá as etapas de diagnóstico, conceito, desenvolvimento e entrega, com aprovação da CONTRATANTE ao fim de cada etapa. Os arquivos finais serão entregues após a quitação dos valores. O registro da marca (INPI) e a pesquisa de anterioridade não estão incluídos, salvo [CAMPO A PREENCHER — se incluídos].$b$, true),
  (p_agency, 'Sites e landing pages — condições', 'servico', $b$O escopo de páginas e funcionalidades é o descrito na cláusula de Objeto e escopo; funcionalidades adicionais serão orçadas à parte. Textos e imagens serão fornecidos por [CAMPO A PREENCHER — CONTRATANTE ou CONTRATADA]. Hospedagem e domínio correm por conta de [CAMPO A PREENCHER]. Suporte e correções após a entrega: [CAMPO A PREENCHER — prazo e abrangência]. Licenças de temas, plugins e ferramentas de terceiros são de responsabilidade de [CAMPO A PREENCHER].$b$, true),
  (p_agency, 'Design e criação — condições', 'servico', $b$Os formatos, dimensões e quantidades de peças são os descritos no escopo. Arquivos-fonte editáveis só serão entregues se expressamente previstos: [CAMPO A PREENCHER — previstos ou não].$b$, true),
  (p_agency, 'Consultoria — condições', 'servico', $b$Os entregáveis consistem em análises e recomendações; a decisão e a execução cabem à CONTRATANTE. Reuniões e encontros: [CAMPO A PREENCHER — quantidade e duração]. Não há garantia de resultado decorrente da implementação das recomendações.$b$, true);

  for t in select * from (values
      ('Social Media (recorrente)',  'social_media', 'Gestão de redes sociais em contrato recorrente.',      'Social media — condições'),
      ('Tráfego Pago (recorrente)',  'trafego_pago', 'Gestão de anúncios em contrato recorrente.',            'Tráfego pago — condições'),
      ('Branding (projeto)',         'branding',     'Projeto de identidade visual.',                          'Branding — condições'),
      ('Site institucional (projeto)','site',        'Desenvolvimento de site institucional.',                 'Sites e landing pages — condições'),
      ('Landing page (projeto)',     'landing_page', 'Desenvolvimento de landing page.',                       'Sites e landing pages — condições'),
      ('Design e criação',           'design',       'Peças e materiais de design.',                           'Design e criação — condições'),
      ('Consultoria',                'consultoria',  'Serviços de consultoria.',                                'Consultoria — condições'),
      ('Prestação de serviços (geral)','geral',      'Modelo geral, sem cláusula específica de serviço.',      null)
    ) as v(name, stype, descr, svc) loop
    insert into public.contract_templates (agency_id, name, service_type, description, is_starter)
      values (p_agency, t.name, t.stype, t.descr || ' MODELO-BASE: revisão jurídica obrigatória.', true) returning id into tid;
    titles := before_svc || case when t.svc is null then '{}'::text[] else array[t.svc] end || after_svc;
    for i in 1..array_length(titles, 1) loop
      insert into public.contract_template_clauses (template_id, clause_id, position)
        select tid, id, i from public.clause_library where agency_id = p_agency and title = titles[i];
    end loop;
  end loop;
end $$;

create or replace function app.agencies_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin perform app.seed_roles(new.id); perform app.seed_agency(new.id); perform app.seed_contracts(new.id); return null; end $$;

do $$ declare a uuid; begin for a in select id from public.agencies loop perform app.seed_contracts(a); end loop; end $$;

-- =====================================================================================================
-- F. RLS
-- =====================================================================================================
alter table public.clause_library            enable row level security;
alter table public.contract_templates        enable row level security;
alter table public.contract_template_clauses enable row level security;
alter table public.contracts                 enable row level security;
alter table public.contract_versions         enable row level security;
alter table public.contract_events           enable row level security;

create policy clauses_select on public.clause_library for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.read'));
create policy clauses_write  on public.clause_library for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('contracts.templates')) with check (agency_id = (select app.current_agency_id()) and app.can('contracts.templates'));
create policy ctemplates_select on public.contract_templates for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.read'));
create policy ctemplates_write  on public.contract_templates for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('contracts.templates')) with check (agency_id = (select app.current_agency_id()) and app.can('contracts.templates'));
create policy ctclauses_select on public.contract_template_clauses for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.read'));
create policy ctclauses_write  on public.contract_template_clauses for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('contracts.templates')) with check (agency_id = (select app.current_agency_id()) and app.can('contracts.templates'));

create policy contracts_select on public.contracts for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.read'));
create policy contracts_insert on public.contracts for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.can('contracts.write'));
create policy contracts_update on public.contracts for update to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('contracts.write')) with check (agency_id = (select app.current_agency_id()) and app.can('contracts.write'));
create policy contracts_delete on public.contracts for delete to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.write') and status = 'rascunho');
create policy cversions_select on public.contract_versions for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.read'));
create policy cversions_insert on public.contract_versions for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.can('contracts.write'));
create policy cevents_select on public.contract_events for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('contracts.read'));
create policy cevents_insert on public.contract_events for insert to authenticated with check (agency_id = (select app.current_agency_id()) and app.can('contracts.write'));

-- =====================================================================================================
-- G. Privilégios
-- =====================================================================================================
grant select, insert, update, delete on public.clause_library, public.contract_templates, public.contract_template_clauses, public.contracts, public.contract_versions, public.contract_events to authenticated;
grant all on public.clause_library, public.contract_templates, public.contract_template_clauses, public.contracts, public.contract_versions, public.contract_events to service_role;
revoke all on public.clause_library, public.contract_templates, public.contract_template_clauses, public.contracts, public.contract_versions, public.contract_events from anon;
revoke execute on function app.contracts_number(), app.contracts_before(), app.contracts_after(), app.fmt_brl(numeric), app.fmt_date(date), app.render_vars(text, jsonb), app.seed_contracts(uuid) from public, anon;
grant execute on function app.contracts_number(), app.contracts_before(), app.contracts_after(), app.fmt_brl(numeric), app.fmt_date(date), app.render_vars(text, jsonb), app.seed_contracts(uuid) to authenticated, service_role;
revoke execute on function public.contract_generate(uuid, uuid, uuid, date, text), public.contract_snapshot(uuid, text), public.contract_renew(uuid, int), public.run_contract_scans() from public, anon;
grant execute on function public.contract_generate(uuid, uuid, uuid, date, text), public.contract_snapshot(uuid, text), public.contract_renew(uuid, int) to authenticated;
grant execute on function public.run_contract_scans() to service_role;
