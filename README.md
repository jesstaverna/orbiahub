# orbiahub.

**Sua agência inteira. Um só lugar.** — SaaS multi-agência para operação de agências de marketing: CRM, propostas, clientes, financeiro, metas e automações 24/7 sobre Next.js + Supabase (PostgreSQL com RLS por agência).

**Estado:** núcleo comercial/financeiro implementado e testado + **multi-tenant (P0)**. Contratos, projetos, estratégia, anúncios, conteúdo, equipe, portal do cliente e agentes de IA estão planejados; as telas exibem “não implementado” — **nada é simulado**.

| Leia | Para quê |
|---|---|
| [`docs/AUDITORIA.md`](docs/AUDITORIA.md) | Matriz de funcionalidades (estado real), diagnóstico, o que foi feito e testado |
| [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) | Modelo multi-tenant, entidades dos módulos que faltam, priorização P0–P3 |
| [`docs/DECISOES.md`](docs/DECISOES.md) | Decisões técnicas e consequências |
| [`docs/DEPLOY.md`](docs/DEPLOY.md), [`docs/PRIMEIROS-PASSOS.md`](docs/PRIMEIROS-PASSOS.md) | Publicação, operação e segurança |

## O que existe
- **Plataforma:** agências, planos com limites, administrador da plataforma (`/plataforma`) sem acesso aos dados de negócio; suspensão de agência.
- **Por agência (isolado por RLS + triggers):** login e **perfis com permissões configuráveis** (Administrador, Gestor/Head, Comercial, Financeiro, Designer, Tráfego, Cliente + perfis próprios) · identidade visual (nome e cor) · Dashboard com dados reais · CRM (kanban, lista, calendário, anti-duplicidade, motivo de perda, lembretes) · Clientes (visão 360°) · Propostas (modelos, itens, desconto autorizado por admin, versões, link exclusivo com a marca da agência, aceite/pedido de alteração, PDF por impressão) · Financeiro (previsto/emitido/recebido, parcelas, recorrências, inadimplência, comprovantes privados) · Metas · Fila de automações + alertas · Auditoria.
- Tipografia: **Helvetica** (Helvetica Neue → Helvetica → Arial).

**Pendente / não conectado:** contratos, projetos, portal, Brand Center, anúncios, conteúdo, IA; RD Station/Conversas, Clicksign/ZapSign, Meta/Google Ads, Asaas (dependem de contas e credenciais); validação de convite/MFA contra Supabase real; códigos de recuperação do MFA.

## Rodando
```bash
cp .env.example .env.local      # preencha com um projeto Supabase (aplique supabase/migrations/*.sql)
npm install
npm run dev
```

## Testes
| Camada | Comando | O que cobre |
|---|---|---|
| Regras puras e marca | `npm test` | normalização, totais, parcelas, metas, cor/contraste da agência |
| Banco | `npm run test:db` | 4 cenários: base · multi-tenant (suíte original sob RLS + isolamento A/B/C, planos, suspensão) · dados legados → migração → rollback · rollback em banco vazio |
| Build | `npm run typecheck && npm run build` | TypeScript e produção |
| Worker / consultas | `PGRST_URL=… npx vitest run` · `node supabase/tests/api_smoke.mjs` | exigem PostgREST local; **não rodados na última entrega** |

**Não testado:** fluxo completo no navegador contra Supabase hospedado (Auth/convite, Storage, Cron reais).

## Migrations
`supabase/migrations/` (0001–0005 base, **0006 multi-tenant**, **0007 link público**, **0008 papéis e permissões**). Rollbacks: `supabase/rollback/`. `supabase/setup.sql` é a concatenação para colar no SQL Editor (projeto vazio).
