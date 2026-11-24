-- Candidate migration: promote with Supabase CLI only in a dedicated staging project.
-- Requires the existing multi-tenant, roles and catalog migrations.
begin;
create table public.marketing_brands (
  id uuid primary key default gen_random_uuid(),
  agency_id uuid not null default app.current_agency_id() references public.agencies(id),
  client_id uuid references public.clients(id) on delete restrict,
  name text not null check (char_length(btrim(name)) between 1 and 100),
  segment text not null default '' check (char_length(segment) <= 120),
  tone_of_voice text not null default '' check (char_length(tone_of_voice) <= 4000),
  primary_color text not null default '#7C5CFF' check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  secondary_color text not null default '#EDE6FF' check (secondary_color ~ '^#[0-9A-Fa-f]{6}$'),
  timezone text not null default 'America/Sao_Paulo',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index marketing_brands_name_unique on public.marketing_brands (agency_id, lower(btrim(name)));
create index marketing_brands_client_idx on public.marketing_brands (client_id);
create trigger marketing_brands_guard before insert or update on public.marketing_brands
for each row execute function app.agency_guard('client_id:clients');
create trigger marketing_brands_audit after insert or update or delete on public.marketing_brands
for each row execute function app.audit();
alter table public.marketing_brands enable row level security;
revoke all on public.marketing_brands from public, anon, authenticated;
grant select on public.marketing_brands to authenticated;
grant insert (client_id,name,segment,tone_of_voice,primary_color,secondary_color,active) on public.marketing_brands to authenticated;
grant update (client_id,name,segment,tone_of_voice,primary_color,secondary_color,active) on public.marketing_brands to authenticated;
create policy marketing_brands_select on public.marketing_brands for select to authenticated
using (agency_id = (select app.current_agency_id()) and (select app.can('app.access')) and (select app.can('brand.access')));
create policy marketing_brands_insert on public.marketing_brands for insert to authenticated
with check (agency_id = (select app.current_agency_id()) and (select app.can('app.access')) and (select app.can('brand.access')) and (select app.can('settings.manage')));
create policy marketing_brands_update on public.marketing_brands for update to authenticated
using (agency_id = (select app.current_agency_id()) and (select app.can('app.access')) and (select app.can('brand.access')) and (select app.can('settings.manage')))
with check (agency_id = (select app.current_agency_id()) and (select app.can('app.access')) and (select app.can('brand.access')) and (select app.can('settings.manage')));
commit;
