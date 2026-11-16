# orbiahub. — Auditoria, diagnóstico e plano

> Data: 2026-11-16 · Escopo: tudo o que foi encontrado nas contas GitHub, Lovable e Supabase disponíveis nesta sessão.

## 0. O que foi (e o que não foi) encontrado

| Fonte | Resultado |
|---|---|
| GitHub (10 repositórios) | **Nenhum repositório OrbiaHub.** Única menção: card em `guria-do-design/linkbio/index.html` apontando para `orbiahub.app.com.br`. |
| Lovable (25 projetos) | **Nenhum projeto OrbiaHub.** O mais próximo é o *Muvens Admin Hub* (painel interno, tema escuro/verde-limão). Não foi auditado a fundo. |
| Supabase (2 projetos) | `Muvens Agência` e `guria-do-design`. Nenhum do OrbiaHub. **Nada foi lido nem alterado neles.** |
| Código reaproveitável | **MUVENS OS** (`desktop-tutorial`): Next.js 15 + Supabase, Fase 1 implementada e com testes. Foi a base desta evolução. |

**Consequência:** o orbiahub. não tinha código próprio. Esta auditoria avalia o **MUVENS OS como base** (lido por inteiro: 5 migrações, ~1.000 linhas de SQL, 2 suítes de teste SQL, app Next.js) contra a especificação do orbiahub.
A identidade do orbiahub **não estava em nenhum repositório**; depois da auditoria o brand board foi enviado e aplicado (paleta Graphite/Lilac/Pale Lilac/Off White, logos). A cor de destaque é **token por agência**. Tipografia: **Helvetica sempre**, por instrução sua — o brand board cita Inter (ver DECISOES #12–13).

## 1. Matriz de funcionalidades

Legenda do estado: ✅ implementada e funcional · 🟡 parcial · 🎨 apenas interface · ❌ não implementada · 🔧 precisa de refatoração · ❓ não verificado.
"Verificação" indica como o estado foi confirmado: **T** = teste automatizado executado, **L** = leitura de código, **D** = descrito no README/docs sem teste próprio.

| Módulo | Funcionalidade | Estado | Problema identificado | Alteração necessária | Prio |
|---|---|---|---|---|---|
| SaaS | Multi-tenant / isolamento entre agências | ✅ (agora) | Base era single-tenant: sem `agency_id`, RLS só por papel; primeiro usuário virava admin de tudo. | **Feito (0006):** `agencies`, `agency_id` em todas as tabelas, RLS por agência, triggers anti-referência cruzada. **T** | P0 |
| SaaS | Usuário ↔ agência | ✅ (agora) | Inexistente. | **Feito:** `profiles.agency_id`; `agency_add_member`; 1 usuário = 1 agência. | P0 |
| SaaS | Admin da plataforma | ✅ (agora) | Inexistente. | **Feito:** `is_platform_admin`, `/plataforma`, `platform_create_agency/set_agency`. Não lê dados de negócio (LGPD). **T** | P0 |
| SaaS | Planos e limites | 🟡 | Inexistente. | **Feito:** `plans` + trava de usuários/clientes (erro 53400). Falta: cobrança, mais limites (armazenamento, IA), upgrade self-service. | P0→P3 |
| SaaS | Identidade visual por agência | 🟡 | Cor fixa da Muvens. | **Feito:** cor de destaque por agência (nome + cor em menu, propostas públicas), contraste automático. Falta: logo, tipografia de documentos. **T** (unit) | P1 |
| SaaS | Papéis e permissões configuráveis | 🔧 | 6 papéis fixos em `CHECK`; matriz de permissão no código (`permissions.ts`) e nas policies. Sem "Gestor/Head" nem permissões editáveis. | Tabela de papéis/permissões por agência + funções `app.can(permission)` usadas por RLS e UI. | P1 |
| SaaS | Auditoria | 🟡 | `audit_log` cobre perfis, clientes, serviços, leads, propostas, lançamentos, metas, agências; UI mostra só 15 linhas; sem filtros/exportação. | Tela de auditoria filtrável + exportação; cobrir novas tabelas. | P1 |
| SaaS | Segurança de sessão | 🟡 | Sem MFA; convite por e-mail depende do fluxo de senha do Supabase (callback/definir senha **não existe** no app). ❓ | MFA para admins; rota de callback + "definir senha". | P0 |
| SaaS | LGPD | 🟡 | RLS + auditoria + bucket privado ok; faltam base legal, retenção, exportação/exclusão de titular, registro de consentimento. | Rotinas de titular + política de retenção por agência. | P1 |
| SaaS | Cobrança/assinatura do próprio SaaS | ❌ | — | Integração de pagamento (a definir). | P3 |
| A. Dashboard | Indicadores reais (MRR, recebido, a receber, atraso, contratado, funil, negociações) | ✅ | Números vêm de `dashboard_metrics` (RLS aplicada). **T** | — | — |
| A. Dashboard | Projetos, demandas atrasadas, aprovações, capacidade, contratos a vencer, anúncios | ❌ | Dependem de módulos inexistentes. | Entram com cada módulo. | P1–P2 |
| A. Dashboard | Alertas inteligentes | 🟡 | 5 varreduras (atraso, lead parado, proposta parada, lembretes, expiração) **T**; sem alertas de projeto/campanha/contrato. | Novas varreduras por módulo. | P1 |
| B. CRM | Pipeline configurável (etapas, probabilidade) | ✅ | Edita em Configurações. **L** | — | — |
| B. CRM | Leads: kanban, lista, calendário, anti-duplicidade, motivo de perda, lembretes, histórico | ✅ | Regras no banco. **T** | — | — |
| B. CRM | Empresas/contatos múltiplos | 🟡 | `client_contacts` existe; lead é uma pessoa+empresa em texto. **L** | Modelo `companies`/`contacts` e conversão lead→empresa. | P1 |
| B. CRM | Reuniões / atividades / follow-ups | 🟡 | Interações (inclui `reuniao`) e lembretes; sem agenda/integração de calendário. | Atividades com tipo/prazo/responsável. | P1 |
| B. CRM | Conversão lead→cliente | ✅ | Automática ao aceitar a proposta. **T** | — | — |
| B. CRM | Ficha 360° do cliente | 🟡 | Mostra dados, serviços, financeiro. Sem projetos, contratos, arquivos, campanhas. **L** | Preencher conforme módulos nascem. | P1 |
| B. CRM | Head responsável pela conta | ❌ | Só `owner_id` no lead/proposta. | `clients.head_id` + visão por head. | P1 |
| B. CRM | Identidade visual/documentos/arquivos do cliente | ❌ | Brand Center não existe. | Storage por agência/cliente. | P1 |
| C. Propostas | Templates, itens, desconto autorizado, totais por trigger, versões, eventos | ✅ | **T** | — | — |
| C. Propostas | Link exclusivo, aceite/pedido de alteração, expiração | ✅ | Só por RPC (anon sem tabelas). Agora com marca da agência. **T** | Rate limit no endpoint público; rotação de token. | P0 |
| C. Propostas | Aprovação digital | 🟡 | Registra nome, e-mail, data, IP. **Não é assinatura certificada** e não deve ser descrita assim. | Usar assinatura eletrônica real (ver D). | P1 |
| C. Propostas | PDF | 🟡 | "Imprimir → Salvar como PDF" do navegador. | Geração no servidor (a definir). | P2 |
| C. Propostas | Catálogo de serviços / pacotes | ❌ | Itens são digitados a cada proposta. | `service_catalog`, `packages` por agência + preço padrão. | P1 |
| C. Propostas | Editor visual | 🎨 | Formulário com seções; sem editor visual. | Evoluir após catálogo. | P2 |
| C. Propostas | Proposta aceita → contrato | ❌ | Gera cliente/serviços/recebíveis (`activate_proposal` **T**), mas contrato não existe; job `proposal.accepted` é handler vazio. | Handler cria rascunho de contrato. | P1 |
| D. Contratos | Tudo (modelos, cláusulas, variáveis, vigência, renovação, assinatura, alertas) | ❌ | Rota `/contratos` é página "não implementado". | Módulo novo (ver ARQUITETURA §3). **Assinatura depende de provedor e credenciais.** Modelos jurídicos sempre editáveis e com aviso de revisão profissional. | P1 |
| E. Projetos | Projetos, tarefas, kanban, calendário, tempo, aprovações, briefings | ❌ | Rotas são páginas "não implementado". | Módulo novo (ver ARQUITETURA §3). | P1 |
| E. Projetos | Atraso interno × atraso do cliente | ❌ | — | Campo `blocked_by` (agência/cliente) e SLA por etapa. | P1 |
| F. Estratégia/RevOps | Hub por cliente, campanhas, funil, calendário estratégico | ❌ | — | Módulo novo. | P2 |
| G. Anúncios | Contas, campanhas, métricas Meta/Google | ❌ | Placeholder. Depende de tokens/apps aprovados. Nenhum dado simulado. | Fase de leitura primeiro. | P2→P3 |
| H. Criador de anúncios | Briefing, variações, aprovação | ❌ | — | Módulo novo + agente de IA depois. | P2 |
| I. Conteúdo | Calendário editorial, aprovação, agendamento | ❌ | `/calendario` é de produção, placeholder. | Módulo novo. | P2 |
| J. Equipe | Cadastro e papéis | 🟡 | Só usuários/papéis. Sem especialidade, capacidade, ausências. | `team_members`, `availability`, `time_entries`. | P2 |
| K. Financeiro | Lançamentos, recorrências, parcelas, previsto→emitido→recebido, atraso, comprovantes (bucket privado) | ✅ | **T** | — | — |
| K. Financeiro | Rentabilidade por cliente/projeto, horas × realizado, margem | ❌ | Sem horas/custos por projeto. | Depende de projetos e `time_entries`. | P2 |
| K. Financeiro | Relatórios/exportação | ❌ | — | CSV/PDF por período. | P2 |
| L. Portal do cliente | Login, projetos, aprovações, arquivos | ❌ | Só existem o papel `cliente`, `profiles.client_id` e policy de leitura do próprio cliente. Sem UI. | Módulo novo; **visibilidade controlada pela agência** por item. | P1 |
| M. IA | 12 agentes | ❌ | `ANTHROPIC_API_KEY` só listada como pendente. | Camada de agentes com ferramentas de leitura sob RLS e ações críticas como rascunho. | P3 |
| Automação | Fila 24/7, retentativa, backoff, `dead`, jobs travados | ✅ | **T** (SQL). Worker TS testado só em unitário/skip: PostgREST não disponível aqui. ❓ | Rodar `worker.int.test` em homologação. | P0 |
| Infra | CI | 🟡 | `ci.yml` roda typecheck, vitest, build e testes SQL. Não foi executado no GitHub nesta sessão. ❓ | Verificar na primeira execução. | P0 |
| UX | Responsividade / acessibilidade | ❓ | Layout tem menu móvel e `aria`; **não validei no navegador** (sem Supabase para logar). | Revisar em dispositivos reais. | P1 |

## 2. Diagnóstico de arquitetura

**Pontos fortes (mantidos):** regras de negócio no banco (constraints, triggers, RLS, RPC `security definer`), UI fina com Server Actions, fila de jobs no Postgres, link público só por RPC, auditoria, testes SQL de regras e de RLS por perfil, páginas honestas para o que não existe ("não implementado", sem dados simulados).

**Problemas encontrados:**
1. **Single-tenant** — ver matriz. Corrigido na 0006 (§ abaixo).
2. **Seeds globais** (funil e categorias) em migração: viraram sementes **por agência** (`app.seed_agency`).
3. **Numeração de proposta global** (`sequence`): passou a **por agência** (`agency_counters`).
4. **Funções `security definer`** (`activate_proposal`, notificações, varreduras do worker) enxergavam todas as linhas: reescritas com escopo de agência.
5. **Unicidades globais** (e-mail/telefone de lead, CNPJ de cliente, posição de etapa, nome de categoria, metas): viraram **por agência** — duas agências podem ter o mesmo lead.
6. **Storage**: comprovantes sem prefixo de tenant — agora `<agency_id>/...` exigido pela policy.
7. **Matriz de permissão duplicada** (TypeScript + policies SQL) e papéis fixos → plano P1.
8. **Ações do portal/contrato/projetos** apontam para módulos que ainda não existem → mantidas como páginas honestas.

**Risco residual conhecido:** o fluxo de convite por e-mail (definir senha) não existe no app; a criação de usuário depende do Supabase Auth (ver DEPLOY).

## 3. O que foi implementado nesta entrega (P0 — segurança e integridade)

Migration `20261116000006_multitenancy.sql` (+ rollback testado):

- **Tabelas:** `plans`, `agencies`, `agency_counters`; colunas `profiles.agency_id`, `profiles.is_platform_admin`; `agency_id` em 16 tabelas de negócio + `jobs` e `audit_log`.
- **Isolamento:** todas as policies exigem `agency_id = app.current_agency_id()`; agência suspensa ou usuário inativo perdem acesso imediato.
- **Integridade entre tenants (no banco, não na UI):** triggers `agency_inherit` (filhas herdam do pai) e `agency_guard` (recusam FK para outra agência e mudança de `agency_id`).
- **Onboarding seguro:** o primeiro usuário vira admin **da plataforma**; os demais ficam sem agência (= sem acesso) até serem vinculados. `user_metadata` **não** é usado para autorização (é editável pelo usuário).
- **Operações de plataforma:** `platform_create_agency`, `platform_set_agency`, `agency_add_member` — únicos caminhos para alterar vínculo de agência.
- **Migração de dados existentes:** instalação single-tenant com dados vira "Agência padrão" sem perda e sem disparar triggers; contador de propostas continua do maior número. **T**
- **Reversível:** `supabase/rollback/20261116000006_multitenancy.down.sql` (gerado das definições originais); aborta se houver mais de uma agência. **T**

App: `/plataforma`, Configurações (agência, plano/uso, adicionar usuário), cor/nome da agência no menu e nas propostas, comprovantes por agência, login com marca orbiahub.

## 4. Testes executados (esta entrega)

| Teste | Resultado |
|---|---|
| `npm run test:db` — 4 cenários: (1) base single-tenant; (2) multi-tenant: suíte original inteira sob RLS por agência + isolamento A/B/C; (3) dados legados → migração → rollback; (4) rollback em banco vazio → suíte original | **Todos passaram** |
| Teste de mutação: remover o filtro de agência da policy de `leads` | **Suíte falhou como esperado** (prova que os testes detectam vazamento) |
| `npm test` (vitest) | 16 passaram, 2 ignorados (worker integra com PostgREST, não disponível aqui) |
| `npm run typecheck` / `npm run build` | OK (inclui `/plataforma`) |

**Não verificado:** navegador contra Supabase hospedado (Auth, convite, Storage, Cron); `api_smoke.mjs` e `worker.int.test.ts` (exigem PostgREST); responsividade visual; CI no GitHub.
