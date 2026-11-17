-- ORBIAHUB — 0009 Catálogo de serviços e pacotes (alimenta propostas; depois contratos e projetos)
--
-- * service_catalog: serviços da agência (recorrente/avulso, preço base, entregáveis padrão). O preço é da AGÊNCIA: nenhum valor é pré-cadastrado.
-- * packages / package_items: pacotes comerciais (serviços + quantidade + preço opcional por item).
-- * proposal_items.service_id: origem do item. O item guarda uma CÓPIA (descrição, cobrança, quantidade, preço): mudar o catálogo
--   nunca altera uma proposta já montada ou enviada.
-- * public.proposal_add_from_catalog: inclui serviço ou pacote na proposta (atômico, sob a RLS do usuário).
-- * Permissões novas: catalog.read, catalog.manage.
-- * Reversível: supabase/rollback/20261116000009_service_catalog.down.sql

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
    'catalog.read', 'catalog.manage',   -- catálogo de serviços e pacotes
    'finance.access',
    'goals.read', 'goals.manage',
    'audit.read', 'automations.read',
    'settings.manage',
    'brand.access', 'ads.access', 'reports.access', 'ai.access'
  ]
$$;

-- novos agências: padrões incluem o catálogo (comercial lê; gestor e admin gerenciam; financeiro lê)
create or replace function app.seed_roles(p_agency uuid) returns void language plpgsql security definer set search_path = public as $$
declare v_all text[] := app.all_permissions();
begin
  insert into public.roles (agency_id, key, name, permissions, is_system) values
    (p_agency, 'admin',      'Administrador',    v_all, true),
    (p_agency, 'gestor',     'Gestor / Head',    array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','catalog.read','catalog.manage','goals.read','brand.access','ads.access','reports.access','ai.access'], true),
    (p_agency, 'comercial',  'Comercial',        array['app.access','clients.read','clients.write','clientservices.read','crm.access','proposals.read','proposals.write','catalog.read','goals.read','brand.access','reports.access','ai.access'], true),
    (p_agency, 'financeiro', 'Financeiro',       array['app.access','clients.read','clients.write','clientservices.read','clientservices.write','proposals.read','catalog.read','finance.access','goals.read','reports.access','ai.access'], true),
    (p_agency, 'designer',   'Designer',         array['app.access','clients.read','brand.access'], true),
    (p_agency, 'trafego',    'Gestor de Tráfego',array['app.access','clients.read','ads.access','reports.access'], true),
    (p_agency, 'cliente',    'Cliente',          '{}', true)
  on conflict (agency_id, key) do nothing;
end $$;

-- agências existentes: papéis de SISTEMA ganham os novos códigos (papéis personalizados não são tocados)
update public.roles r set permissions = (select array_agg(distinct x) from unnest(r.permissions || p.add) x)
  from (values ('admin',      array['catalog.read','catalog.manage']),
               ('gestor',     array['catalog.read','catalog.manage']),
               ('comercial',  array['catalog.read']),
               ('financeiro', array['catalog.read'])) as p(key, add)
 where r.is_system and r.key = p.key;

-- =====================================================================================================
-- B. Tabelas
-- =====================================================================================================
create table public.service_catalog (
  id           uuid primary key default gen_random_uuid(),
  agency_id    uuid not null default app.current_agency_id() references public.agencies(id) on delete restrict,
  name         text not null check (btrim(name) <> ''),
  category     text not null default 'outro'
               check (category in ('social_media','trafego_pago','branding','site','landing_page','design','consultoria','outro')),
  description  text,
  deliverables text[] not null default '{}',
  billing      text not null default 'pontual' check (billing in ('pontual','mensal')),
  unit_price   numeric(14,2) not null default 0 check (unit_price >= 0),     -- 0 = "sob consulta": a proposta não envia com preço zero
  active       boolean not null default true,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index service_catalog_name_uidx on public.service_catalog (agency_id, lower(name));
create index service_catalog_agency_idx on public.service_catalog (agency_id, active);

create table public.packages (
  id           uuid primary key default gen_random_uuid(),
  agency_id    uuid not null default app.current_agency_id() references public.agencies(id) on delete restrict,
  name         text not null check (btrim(name) <> ''),
  description  text,
  active       boolean not null default true,
  created_by   uuid references public.profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index packages_name_uidx on public.packages (agency_id, lower(name));
create index packages_agency_idx on public.packages (agency_id, active);

create table public.package_items (
  id                  uuid primary key default gen_random_uuid(),
  agency_id           uuid not null references public.agencies(id) on delete restrict,   -- herdado do pacote (trigger)
  package_id          uuid not null references public.packages(id) on delete cascade,
  service_id          uuid not null references public.service_catalog(id) on delete restrict,
  quantity            numeric(10,2) not null default 1 check (quantity > 0),
  unit_price_override numeric(14,2) check (unit_price_override is null or unit_price_override >= 0),   -- null = preço do catálogo
  position            int not null default 0,
  unique (package_id, service_id)
);
create index package_items_agency_idx on public.package_items (agency_id);
create index package_items_package_idx on public.package_items (package_id, position);

alter table public.proposal_items add column service_id uuid references public.service_catalog(id) on delete set null;

-- triggers: updated_at, auditoria, integridade entre agências
create trigger trg_service_catalog_touch before update on public.service_catalog for each row execute function app.touch_updated_at();
create trigger trg_packages_touch before update on public.packages for each row execute function app.touch_updated_at();
create trigger trg_service_catalog_audit after insert or update or delete on public.service_catalog for each row execute function app.audit();
create trigger trg_packages_audit after insert or update or delete on public.packages for each row execute function app.audit();
create trigger trg_package_items_audit after insert or update or delete on public.package_items for each row execute function app.audit();
create trigger trg_01_agency_guard before insert or update on public.service_catalog for each row execute function app.agency_guard();
create trigger trg_01_agency_guard before insert or update on public.packages for each row execute function app.agency_guard();
create trigger trg_00_agency_inherit before insert on public.package_items for each row execute function app.agency_inherit('package_id', 'packages');
create trigger trg_01_agency_guard before insert or update on public.package_items for each row execute function app.agency_guard('service_id:service_catalog');
drop trigger trg_01_agency_guard on public.proposal_items;
create trigger trg_01_agency_guard before insert or update on public.proposal_items for each row execute function app.agency_guard('service_id:service_catalog');

-- =====================================================================================================
-- C. RLS (mesmas regras: agência + permissão)
-- =====================================================================================================
alter table public.service_catalog enable row level security;
alter table public.packages        enable row level security;
alter table public.package_items   enable row level security;

create policy catalog_select on public.service_catalog for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('catalog.read'));
create policy catalog_write  on public.service_catalog for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('catalog.manage')) with check (agency_id = (select app.current_agency_id()) and app.can('catalog.manage'));
create policy packages_select on public.packages for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('catalog.read'));
create policy packages_write  on public.packages for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('catalog.manage')) with check (agency_id = (select app.current_agency_id()) and app.can('catalog.manage'));
create policy pkgitems_select on public.package_items for select to authenticated using (agency_id = (select app.current_agency_id()) and app.can('catalog.read'));
create policy pkgitems_write  on public.package_items for all    to authenticated
  using (agency_id = (select app.current_agency_id()) and app.can('catalog.manage')) with check (agency_id = (select app.current_agency_id()) and app.can('catalog.manage'));

-- =====================================================================================================
-- D. Incluir serviço ou pacote numa proposta (cópia dos dados; SECURITY INVOKER = respeita a RLS de quem chama)
-- =====================================================================================================
create or replace function public.proposal_add_from_catalog(p_proposal uuid, p_service uuid default null, p_package uuid default null, p_quantity numeric default 1)
returns int language plpgsql security invoker as $$
declare v_pos int; v_n int;
begin
  if (p_service is null) = (p_package is null) then raise exception 'Informe um serviço OU um pacote' using errcode = '22023'; end if;
  if coalesce(p_quantity, 1) <= 0 then raise exception 'Quantidade inválida' using errcode = '22023'; end if;
  perform 1 from public.proposals where id = p_proposal;   -- RLS: proposta de outra agência (ou sem permissão) = inexistente
  if not found then raise exception 'Proposta não encontrada'; end if;
  select coalesce(max(position), -1) + 1 into v_pos from public.proposal_items where proposal_id = p_proposal;

  if p_service is not null then
    insert into public.proposal_items (proposal_id, position, description, details, billing, quantity, unit_price, service_id)
    select p_proposal, v_pos, s.name,
           nullif(btrim(concat_ws(E'\n', s.description, case when cardinality(s.deliverables) > 0 then 'Entregáveis: ' || array_to_string(s.deliverables, '; ') end)), ''),
           s.billing, coalesce(p_quantity, 1), s.unit_price, s.id
      from public.service_catalog s where s.id = p_service and s.active;
  else
    insert into public.proposal_items (proposal_id, position, description, details, billing, quantity, unit_price, service_id)
    select p_proposal, v_pos + (row_number() over (order by pi.position, s.name))::int - 1, s.name,
           nullif(btrim(concat_ws(E'\n', s.description, case when cardinality(s.deliverables) > 0 then 'Entregáveis: ' || array_to_string(s.deliverables, '; ') end)), ''),
           s.billing, pi.quantity, coalesce(pi.unit_price_override, s.unit_price), s.id
      from public.package_items pi
      join public.packages pk on pk.id = pi.package_id and pk.active
      join public.service_catalog s on s.id = pi.service_id and s.active
     where pi.package_id = p_package;
  end if;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Serviço ou pacote inexistente, inativo ou vazio' using errcode = '23514'; end if;
  return v_n;
end $$;

-- =====================================================================================================
-- E. Privilégios
-- =====================================================================================================
grant select, insert, update, delete on public.service_catalog, public.packages, public.package_items to authenticated;
grant all on public.service_catalog, public.packages, public.package_items to service_role;
revoke all on public.service_catalog, public.packages, public.package_items from anon;
revoke execute on function public.proposal_add_from_catalog(uuid, uuid, uuid, numeric) from public, anon;
grant execute on function public.proposal_add_from_catalog(uuid, uuid, uuid, numeric) to authenticated;
