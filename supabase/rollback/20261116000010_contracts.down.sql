-- ORBIAHUB — rollback da 0010 (contratos). GERADO a partir das definições da 0008 e da 0009, sem edição.
-- ATENÇÃO — DESTRUTIVO: apaga contratos, versões, eventos, modelos e a biblioteca de cláusulas. Exporte antes se precisar guardar.
delete from public.jobs where type = 'contract.signed';
delete from public.notifications where link like '/contratos/%';
drop function public.run_contract_scans();
drop function public.contract_renew(uuid, int);
drop function public.contract_snapshot(uuid, text);
drop function public.contract_generate(uuid, uuid, uuid, date, text);
drop table public.contract_events;
drop table public.contract_versions;
drop table public.contracts;
drop table public.contract_template_clauses;
drop table public.contract_templates;
drop table public.clause_library;
drop function app.contracts_after();
drop function app.contracts_before();
drop function app.contracts_number();
drop function app.render_vars(text, jsonb);
drop function app.fmt_date(date);
drop function app.fmt_brl(numeric);
drop function app.seed_contracts(uuid);
update public.roles set permissions = array(select x from unnest(permissions) x where x not in ('contracts.read','contracts.write','contracts.approve','contracts.templates'))
 where permissions && array['contracts.read','contracts.write','contracts.approve','contracts.templates'];
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

create or replace function app.agencies_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin perform app.seed_roles(new.id); perform app.seed_agency(new.id); return null; end $$;
