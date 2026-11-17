-- ORBIAHUB — rollback da 0008 (papéis e permissões configuráveis). GERADO a partir das definições da 0001 e da 0006, sem edição.
-- SEGURANÇA: aborta se algum usuário usa papel que não existia antes (gestor ou papel customizado) — reatribua antes de reverter.
do $$ begin
  if exists (select 1 from public.profiles where agency_id is not null and role not in ('admin','comercial','financeiro','designer','trafego','cliente')) then
    raise exception 'Rollback abortado: há usuários com papel gestor/customizado. Reatribua para um dos 6 papéis originais antes de reverter.';
  end if;
end $$;

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

alter table public.profiles drop constraint profiles_role_fk;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','comercial','financeiro','designer','trafego','cliente'));
drop table public.roles;

-- funções originais (0001 e 0006)
create or replace function app.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(app.user_role() in ('admin','comercial','financeiro','designer','trafego'), false)
$$;

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

create or replace function app.agencies_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin perform app.seed_agency(new.id); return null; end $$;

drop function app.can(text);
drop function app.seed_roles(uuid);
drop function app.roles_guard();
drop function app.all_permissions();

-- políticas e storage originais (0006)
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


grant execute on function public.activate_proposal(uuid, date), public.agency_add_member(text, text) to authenticated;
