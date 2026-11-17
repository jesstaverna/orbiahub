-- ORBIAHUB — rollback da 0009 (catálogo de serviços e pacotes). GERADO a partir das definições da 0006 e da 0008, sem edição.
-- ATENÇÃO: apaga o catálogo e os pacotes (as propostas e seus itens permanecem; apenas perdem o vínculo de origem).
drop function public.proposal_add_from_catalog(uuid, uuid, uuid, numeric);
alter table public.proposal_items drop column service_id;
drop trigger trg_01_agency_guard on public.proposal_items;
create trigger trg_01_agency_guard before insert or update on public.proposal_items   for each row execute function app.agency_guard();
drop table public.package_items;
drop table public.packages;
drop table public.service_catalog;
-- remove as permissões do catálogo de TODOS os papéis (sistema e personalizados) antes de restaurar o catálogo antigo
update public.roles set permissions = array_remove(array_remove(permissions, 'catalog.read'), 'catalog.manage')
 where 'catalog.read' = any (permissions) or 'catalog.manage' = any (permissions);
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
