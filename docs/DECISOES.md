# Registro de decisões técnicas

| # | Decisão | Motivo | Consequência |
|---|---|---|---|
| 1 | **Base = MUVENS OS** (Next.js 15 + Supabase) em repositório novo `orbiahub`, em vez de recomeçar | Já tinha regras no banco, RLS por perfil, fila de jobs e testes SQL. Nenhum código OrbiaHub existia. | Reaproveitamento total; diff de multi-tenant concentrado em uma migração. |
| 2 | **Tenant por coluna** (`agency_id`) + RLS, não schema/banco por agência | Simplicidade operacional no Supabase, uma migração para todos, menor custo | Isolamento depende de policies/triggers — por isso o teste de mutação e a suíte A/B/C. |
| 3 | **1 usuário = 1 agência** (`profiles.agency_id`) | Atende o briefing hoje; evita ambiguidade de "agência ativa" na RLS | Consultor em várias agências exigiria tabela `memberships` + seletor de agência (evolução possível). |
| 4 | **Admin da plataforma não lê dados de negócio** | LGPD/minimização; suporte não vê clientes e financeiro das agências | Suporte aprofundado exigirá "acesso delegado" com consentimento e log. |
| 5 | **Não usar `user_metadata` para autorização** | É editável pelo próprio usuário (cadastro aberto permitiria entrar em qualquer agência) | Vínculo só por funções `security definer` e service role. |
| 6 | **Primeiro usuário = admin da plataforma**; demais entram sem agência | Seguro por padrão: conta nova não enxerga nada | Operação precisa de `/plataforma` para criar a 1ª agência. |
| 7 | **Triggers para integridade entre tenants** (`agency_guard`, `agency_inherit`) em vez de FKs compostas | FK composta em ~30 relações geraria migração enorme e frágil | Cada tabela nova precisa registrar o trigger (checklist em ARQUITETURA §3). |
| 8 | **Número de proposta por agência** (`agency_counters`) | Numeração global vaza volume entre clientes e confunde | Contador atômico via `insert … on conflict`. |
| 9 | **Sementes por agência** (`app.seed_agency`) | Funil/categorias editáveis por agência | Migração remove sementes globais; legado recebe tudo na "Agência padrão". |
| 10 | **Planos** como tabela com limites **de exemplo** | Preparar cobrança futura sem inventar preço | Trava só usuários/clientes por ora (erro 53400). |
| 11 | **Cor da agência como token CSS** (`--brand`, `--on-brand`) com contraste automático | "Identidade visual da agência" sem recompilar; texto legível em qualquer cor | Valida `#RRGGBB` (sem CSS arbitrário vindo do banco). Logo/tipografia: pendente. |
| 12 | **Tipografia: Helvetica sempre** (Helvetica Neue → Helvetica → Arial) | Decisão do dono do produto (substitui Inter do briefing) | Já era a fonte do Tailwind; mantida. |
| 13 | **Cor de destaque padrão = a do MUVENS OS** (provisória) | O design system do orbiahub não foi encontrado | Substituir por tokens oficiais quando fornecidos. |
| 14 | **Rollback gerado das definições originais** | Evita erro de digitação ao reverter | Teste em CI: migrar→reverter→suíte original verde. Aborta se >1 agência. |
| 15 | **Aceite de proposta ≠ assinatura certificada** | Não inventar validade legal | Texto/UX devem manter "registro de aceite"; assinatura real só via provedor (P1/P3). |
