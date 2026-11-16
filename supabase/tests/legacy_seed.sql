-- Dados de uma instalação single-tenant (migrações 0001–0005) ANTES de aplicar a 0006.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d1', 'legado-admin@orbiahub.test'),
  ('00000000-0000-0000-0000-0000000000d2', 'legado-comercial@orbiahub.test');
update profiles set role = 'comercial' where email = 'legado-comercial@orbiahub.test';
insert into clients (name, document) values ('Cliente Legado', '11.222.333/0001-81');
insert into leads (name, email, stage_id, owner_id)
  select 'Lead Legado', 'lead@legado.test', id, '00000000-0000-0000-0000-0000000000d2' from pipeline_stages where name = 'Qualificação';
insert into proposals (title, client_display_name, client_id) select 'Proposta Legada 1', 'Cliente Legado', id from clients;
insert into proposals (title, client_display_name) values ('Proposta Legada 2', 'Outro');
insert into proposal_items (proposal_id, description, billing, unit_price, position) select id, 'Serviço legado', 'mensal', 1000, 1 from proposals where title = 'Proposta Legada 1';
insert into fin_transactions (direction, description, amount, due_date, client_id, category_id)
  select 'in', 'Cobrança legada', 100, current_date, c.id, (select id from fin_categories where name = 'Serviços pontuais') from clients c;
insert into goals (period_type, period_start, revenue_target) values ('mensal', date_trunc('month', current_date)::date, 10000);
