# Deploy e operação

## 1. Ambientes
Crie **3 projetos Supabase** (dev, homologação, produção) e 3 deploys do app, cada um com seu `.env` (veja `.env.example`). O schema vem **somente** de `supabase/migrations/` (aplicar na ordem com `supabase db push` ou colando no SQL Editor).

## 2. Primeiro acesso
1. Aplicar as migrações de `supabase/migrations/` (automático pela integração GitHub↔Supabase após o merge na branch configurada, ou manualmente via `supabase db push` / `supabase/setup.sql`; **use apenas um dos caminhos**).
2. Supabase → Authentication → **desativar “Allow new users to sign up”** e criar o primeiro usuário. **O primeiro usuário vira administrador da PLATAFORMA** (sem agência). Os demais entram sem agência = sem acesso a nada.
   - Entre em `/login` com esse usuário: você cai em **/plataforma**. Crie a primeira agência informando o e-mail do proprietário (que já precisa ter conta; com `SUPABASE_SERVICE_ROLE_KEY` configurada o app também envia o convite). Para ser dono da própria agência, use o seu e-mail.
   - O proprietário passa a adicionar a equipe em *Configurações → Usuários* (pelo e-mail). Cada usuário pertence a **uma** agência.
   - **Convite e “Esqueci a senha”** funcionam por `/auth/confirm` → `/definir-senha`. Para isso, em Supabase → *Authentication → Email Templates* troque o link dos templates **Invite user** e **Reset password** por:
     - Invite: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=invite`
     - Reset: `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery`
     e confira *Site URL* (passo 4). Sem essa troca o link do e-mail não leva à tela de senha. Alternativa: criar o usuário em *Authentication → Users → Add user* (com senha, *Auto Confirm*).
   - **Verificação em duas etapas (TOTP):** cada usuário pode ativar em `/seguranca`; quem ativa passa a digitar o código a cada login. Para **obrigar** administradores (da agência e da plataforma), defina `REQUIRE_MFA_ADMIN=true`. Habilite MFA/TOTP em *Authentication → Providers/Multi-Factor* se estiver desligado.
   - **Link público de proposta:** limite de 120 aberturas e 10 aceites/pedidos por 10 min por token (e por IP). O app repassa o IP do visitante (`x-client-ip`) — necessário para o IP do aceite ser o do cliente, e não o do servidor.
3. Definir variáveis no host: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (**somente servidor**), `CRON_SECRET`, `NEXT_PUBLIC_APP_URL`.
4. Configurar “Site URL” e redirects do Auth para o domínio do app.

## 3. Automações 24/7 (obrigatório)
O worker é `GET/POST /api/worker` com `Authorization: Bearer $CRON_SECRET`. Escolha **um** agendador externo (a cada 5 min):

- **Vercel Cron** (`vercel.json`, já incluído; a Vercel envia `Authorization: Bearer $CRON_SECRET` automaticamente quando `CRON_SECRET` está definido). Verifique no seu plano a frequência mínima permitida para crons.
- **Supabase `pg_cron` + `pg_net`** (independe do host do app):
  ```sql
  select cron.schedule('orbiahub-worker', '*/5 * * * *', $$
    select net.http_post(url := 'https://SEU-APP/api/worker', headers := jsonb_build_object('Authorization', 'Bearer SEU_CRON_SECRET'));
  $$);
  ```
- n8n/Cron externo chamando a mesma URL.

Verificação: `/automacoes` mostra “Última varredura”. Monitore `/api/health` (UptimeRobot/BetterStack).

## 4. Segurança e LGPD — checklist
- [x] RLS em todas as tabelas, **filtrada por agência**; `anon` sem acesso a tabelas (link público só por RPC); service role só no servidor.
- [x] Integridade entre agências por trigger (`agency_guard`/`agency_inherit`); vínculo de agência só por funções `security definer`.
- [x] Limite de requisições no link público (0007) e IP real do visitante na evidência de aceite.
- [x] Auditoria (`audit_log`) das tabelas sensíveis; comprovantes em bucket privado com URL assinada de 60 s.
- [x] Cabeçalhos de segurança (HSTS, X-Frame-Options, nosniff, Referrer-Policy).
- [ ] **A cada nova tabela**: `agency_id` + índice, RLS por agência **e** papel, trigger `agency_guard` com as FKs, auditoria, teste em `rules.test.sql` **e** `tenant.test.sql` (checklist em `docs/ARQUITETURA.md` §3).
- [ ] LGPD: definir base legal e política de retenção para leads (dados pessoais), registrar consentimento de WhatsApp (Fase 3), canal de atendimento ao titular, DPA com operadores (Supabase, hospedagem, RD, IA).
- [ ] Backups: ativar backups diários (Pro) e testar restauração.
- [ ] MFA para administradores (Supabase Auth).

## 5. Testes
```bash
npm test                         # unitários (regras puras)
npm run test:db                  # 4 cenários no PostgreSQL local: base, multi-tenant (isolamento A/B/C), dados legados→migração→rollback, rollback vazio
npm run typecheck && npm run build
PGRST_URL=http://127.0.0.1:3111 npx vitest run       # + worker contra PostgREST local
PGRST_URL=http://127.0.0.1:3111 node supabase/tests/api_smoke.mjs   # consultas das páginas contra PostgREST local
```
PostgREST local: ver cabeçalho de `supabase/tests/api_smoke.mjs`.
