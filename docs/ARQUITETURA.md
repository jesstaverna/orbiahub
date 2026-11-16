# orbiahub. — Arquitetura e plano de evolução

> *Sua agência inteira. Um só lugar.* — SaaS B2B multi-agência. Estado atual e lacunas: [`AUDITORIA.md`](AUDITORIA.md). Decisões: [`DECISOES.md`](DECISOES.md).

## 1. Arquitetura técnica (implementada)

```
 Navegador ──► Next.js 15 (App Router, TS, Tailwind, Helvetica) ──► Supabase
 (equipe, link         │  Server Components + Server Actions        ├─ PostgreSQL (dados, RLS, funções, triggers)
  público, portal)     │  (sessão do usuário → RLS)                  ├─ Auth       (login, JWT)
                       │                                             └─ Storage    (buckets PRIVADOS, pasta raiz = agency_id)
                       ├─ /p/[token]     link público: só RPCs "security definer", sem acesso a tabelas
                       ├─ /plataforma    admin da plataforma: agências e planos (sem dados de negócio)
                       ├─ /api/worker    processador de fila (service role, protegido por CRON_SECRET)
                       └─ /api/health    monitoramento
```

### Modelo multi-tenant
```
 plans ──< agencies ──< profiles (agency_id, role, is_platform_admin)
              │
              └──< TODAS as tabelas de negócio carregam agency_id
                   clients, client_contacts, client_services, pipeline_stages, leads, lead_*,
                   proposals, proposal_*, fin_*, goals, notifications   (+ jobs, audit_log)
```
Garantias **no banco** (não dependem da UI):
1. **RLS** — toda policy exige `agency_id = app.current_agency_id()` + papel. Agência suspensa ⇒ `current_agency_id()` nulo ⇒ nenhum acesso.
2. **Sem referência cruzada** — `agency_guard` recusa FK para linha de outra agência e mudança de `agency_id`; `agency_inherit` faz filhas herdarem do pai.
3. **Só funções `security definer` mudam vínculo** (`platform_create_agency`, `agency_add_member`, `platform_set_agency`); `profiles.agency_id` e `is_platform_admin` não são editáveis pelo usuário.
4. **Link público** só por token de 256 bits via RPC; nunca lê tabelas.
5. **Worker** (service role) sempre grava/notifica na agência do registro.
6. **Storage** — policy exige que a pasta raiz do objeto seja a agência do usuário.

Papéis atuais: `admin` (proprietário/administrador da agência), `comercial`, `financeiro`, `designer`, `trafego`, `cliente`. "Gestor/Head" e permissões configuráveis: P1 (§4).

## 2. Mapa de módulos × estado

| Módulo (briefing) | Rota | Estado |
|---|---|---|
| A. Dashboard executivo | `/dashboard`, `/alertas` | 🟡 dados reais; faltam projetos/contratos/anúncios/capacidade |
| B. CRM e clientes | `/crm`, `/clientes` | 🟡 funil completo; falta empresas/contatos, head da conta, arquivos |
| C. Propostas | `/propostas`, `/p/[token]` | 🟡 sem catálogo/pacotes; PDF por impressão |
| D. Contratos | `/contratos` | ❌ |
| E. Projetos e demandas | `/projetos`, `/calendario` | ❌ |
| F. Estratégia / RevOps | — | ❌ |
| G. Gestão de anúncios | `/trafego` | ❌ (depende de credenciais) |
| H. Criador de anúncios | — | ❌ |
| I. Conteúdo | — | ❌ |
| J. Equipe e capacidade | `/configuracoes` | 🟡 só usuários/papéis |
| K. Financeiro | `/financeiro`, `/metas` | ✅ núcleo; ❌ rentabilidade |
| L. Portal do cliente | `/portal` | ❌ |
| M. Central de IA | `/ia` | ❌ |
| SaaS (tenant, planos, plataforma) | `/plataforma`, `/configuracoes` | ✅ núcleo (P0) |

## 3. Entidades, rotas e regras dos módulos que faltam (projeto)

Convenção para **toda** tabela nova: `agency_id not null default app.current_agency_id()` (ou herdado do pai), índice em `agency_id`, trigger `agency_guard` com as FKs, policies por agência+papel, auditoria, **teste em `rules.test.sql`/`tenant.test.sql`**.

| Módulo | Tabelas | Relações-chave | Regras de negócio |
|---|---|---|---|
| **Catálogo** | `service_catalog` (nome, tipo recorrente/avulso, preço base, entregáveis padrão), `packages`, `package_items` | alimenta `proposal_items` e `contract_services` | preço do catálogo é sugestão; proposta guarda cópia (histórico imutável) |
| **Contratos (D)** | `contract_templates` (tipo: social, tráfego, branding, site, LP…), `clauses` (biblioteca), `contracts` (status, vigência, renovação, `proposal_id`, `client_id`), `contract_versions` (snapshot), `contract_signatures` (provedor, id externo, status) | `proposals`→`contracts`→`projects`; variáveis `{{cliente.nome}}` resolvidas no servidor | rascunho **sempre** com revisão humana; assinatura só via provedor real (Clicksign/ZapSign) — sem provedor configurado, status "aguardando assinatura externa", nunca "assinado"; alertas de vencimento/renovação por varredura |
| **Projetos (E)** | `projects`, `tasks` (+subtarefas `parent_id`, `depends_on`), `task_comments`, `task_files`, `checklists`, `briefings`, `approvals`, `time_entries`, `deliverables` | `contracts`→`projects`→`tasks`; `client_services`→`deliverables` | fluxo: Solicitação→Triagem→Planejamento→Produção→Revisão interna→Aprovação do cliente→Ajustes→Conclusão; **`blocked_by` = `agency`\|`client`** separa atraso interno de pendência do cliente |
| **Estratégia (F)** | `strategies` (por cliente), `personas`, `competitors`, `campaigns`, `campaign_assets` | `campaigns` liga anúncios, LPs, e-mails, conteúdos e entregáveis | checklist de lançamento obrigatório antes de "ativa" |
| **Anúncios (G)** | `ad_accounts`, `ad_campaigns`, `ad_sets`, `ads`, `ad_metrics_daily`, `integration_accounts` (tokens **criptografados**) | `ad_accounts.client_id` | **só leitura/relatórios primeiro**; métrica ausente = `null`, nunca zero simulado; investimento do cliente ≠ receita da agência |
| **Criador de anúncios (H)** | `ad_briefs`, `ad_creatives`, `creative_variants`, aprovação interna/cliente | `campaign_assets` | aprovação em duas etapas; IA apenas sugere |
| **Conteúdo (I)** | `content_plans`, `content_items` (formato, canal, legenda, status, arquivos), `publications` | `projects`/`campaigns` | publicação externa só com integração autorizada |
| **Equipe (J)** | `team_profiles` (especialidade, horas/semana), `availability`, `account_heads` | `time_entries`→capacidade | alerta de sobrecarga = carga prevista > capacidade |
| **Rentabilidade (K)** | views `profitability_by_client/project` | `fin_transactions` × `time_entries` × `contracts` | distinguir **contratado / previsto / recebido / vencido** (já no dashboard) |
| **Portal (L)** | `portal_visibility` (o que cada cliente vê), reuso de projetos/aprovações/arquivos | `profiles.client_id` | **a agência controla item a item**; nada interno é exposto (views dedicadas, não as tabelas) |
| **IA (M)** | `ai_agents`, `ai_conversations`, `ai_runs`, `ai_actions` (rascunhos pendentes) | chamadas no servidor com o JWT do usuário (herda RLS) | **ações críticas/externas viram rascunho com confirmação humana**; log de cada execução |
| **Papéis (SaaS)** | `roles`, `role_permissions`, `app.can(perm)` | substitui `CHECK` de papéis e `permissions.ts` | permissões por agência, aplicadas em RLS e UI |

### Rotas planejadas
`/contratos[/novo|/[id]]`, `/catalogo`, `/projetos[/[id]]`, `/calendario`, `/estrategia/[clienteId]`, `/trafego`, `/anuncios`, `/conteudo`, `/equipe`, `/relatorios`, `/portal/*` (layout próprio, sem sidebar interna), `/ia`.

## 4. Priorização

| Prioridade | Escopo | Estado |
|---|---|---|
| **P0** Segurança e integridade | Multi-tenant + RLS por agência + integridade entre tenants + plataforma + migração/rollback testados. Também **feito:** convite/definir senha/esqueci a senha, MFA TOTP (obrigatório opcional por `REQUIRE_MFA_ADMIN`), limite de requisições do link público + IP real (0007). **Pendentes P0:** `api_smoke` + worker contra PostgREST, primeira execução do CI, validar convite/MFA em Supabase real | ✅ núcleo / ⏳ pendentes |
| **P1** Núcleo operacional | Papéis configuráveis (Gestor/Head); catálogo e pacotes; contratos (modelos, cláusulas, variáveis, proposta→contrato, assinatura via provedor); projetos/demandas/aprovações/tempo; empresas e contatos no CRM; head da conta; portal do cliente; auditoria filtrável; LGPD (titular, retenção) | ⏳ próximo |
| **P2** Crescimento | Estratégia/RevOps; anúncios (leitura Meta/Google); criador de anúncios; calendário de conteúdo; equipe e capacidade; rentabilidade; relatórios/PDF | ⏳ |
| **P3** Escala | Integrações avançadas (RD, Clicksign/ZapSign, Asaas, Meta/Google escrita), 12 agentes de IA, cobrança do SaaS, automações | ⏳ |

### Integrações — pendências externas (nada simulado)
| Integração | O que falta |
|---|---|
| Clicksign / ZapSign | conta + token; escolher provedor |
| Meta Ads / Google Ads | app aprovado, tokens, developer token do Google, acesso às contas dos clientes |
| RD Station / RD Conversas | contas/planos e credenciais |
| Asaas | chave de API (sandbox primeiro) |
| Claude API | `ANTHROPIC_API_KEY` no servidor |
| Cobrança do SaaS | provedor de pagamento a definir |

## 5. Fluxo integrado alvo (lead → renovação)
1. Lead no CRM ✅ → 2. Oportunidade ✅ → 3. Proposta (catálogo P1) 🟡 → 4. Aceite ✅ → 5. **Contrato gerado** ❌ P1 → 6. Assinatura via provedor ❌ P1/P3 → 7. Cliente ativado ✅ (`activate_proposal`) → 8. Serviços geram **projetos/entregáveis** ❌ P1 → 9. Equipe recebe demandas ❌ P1 → 10–12. Estratégia, anúncios/conteúdo e aprovação do cliente ❌ P1–P2 → 13. Resultados ❌ P2 → 14. Rentabilidade 🟡 → 15. Alerta de renovação/expansão ❌ P1/P2.
Os pontos ✅ já compartilham `clients.id` e `agency_id`; nenhum dado é recadastrado entre módulos.

## 6. Automações 24/7 (implementadas)
Gatilhos no banco enfileiram `jobs`/`notifications`; o worker (a cada 5 min) processa a fila e roda a varredura horária **sobre todas as agências ativas**, sempre no escopo da agência do registro. Retentativa com backoff 1-2-4-8 min; após 5 tentativas → `dead` (visível em `/automacoes`); jobs travados há >10 min são recuperados.

## 7. Riscos
- **Link público**: token de 256 bits + limite por token/IP (0007). O limite por IP é “melhor esforço” (quem chama o PostgREST direto pode forjar o cabeçalho); o limite por token não é falsificável.
- **Identidade**: convite, senha e MFA dependem do Supabase Auth e dos templates de e-mail; **ainda não validados contra um Supabase real**.
- **Modelos jurídicos**: sempre editáveis, com aviso de revisão profissional; o sistema **não** atribui validade legal.
- **LGPD**: definir base legal, retenção e canal do titular antes de operar com dados reais de terceiros.
- **Custos** (confirmar nos sites oficiais): Supabase, hospedagem, domínio, provedor de assinatura, Asaas, APIs de IA.
