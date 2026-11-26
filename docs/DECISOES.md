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
| 13 | **Paleta e logos oficiais do orbiahub.** aplicados: Graphite `#0B0B0F`, Lilac `#7C5CFF` (destaque padrão), Pale Lilac `#EDE6FF`, Off White `#FAFAFD`; logos em `public/brand` | Brand board enviado pelo dono do produto | O brand board cita **Inter**; prevalece a instrução explícita **“Helvetica sempre”** (decisão 12). Se quiser Inter, é trocar `fontFamily` em `tailwind.config.ts`. |
| 14 | **Rollback gerado das definições originais** | Evita erro de digitação ao reverter | Teste em CI: migrar→reverter→suíte original verde. Aborta se >1 agência. |
| 16 | **Permissões, não papéis, decidem tudo** (`app.can`) | Papéis fixos não atendem agências de tamanhos diferentes | Papéis de sistema reproduzem exatamente o comportamento anterior (suíte original passa sem alteração); `admin`/`cliente` fixos impedem lockout. |
| 17 | **Catálogo de permissões duplicado (SQL + TS) com teste de paridade** | O menu precisa conhecer as permissões; o banco é a fonte da verdade | Teste falha se divergirem; módulo novo = novo código nos dois lados. |
| 18 | **Item de proposta = cópia do catálogo** (`service_id` só registra a origem) | Proposta enviada é documento: alterar preço no catálogo não pode mudar o que o cliente viu/aceitou | Excluir serviço mantém o item (FK `set null`); serviço dentro de pacote não é apagável (desative). |
| 19 | **Contrato: aprovação humana obrigatória e travada no banco** (`contracts_before`) | Texto jurídico gerado por modelo não pode seguir adiante com lacunas nem sem alguém responsável ter revisado | Trava de conteúdo ao aprovar; voltar à revisão anula a aprovação; quem aprova/quando fica registrado. |
| 20 | **O sistema não assina**: só registra “assinado fora do sistema” (manual) com evidência | Não inventar validade legal; assinatura eletrônica exige provedor real | `signature_method='provider'` só por service role (integração futura); usuário que tentar é recusado. |
| 21 | **Modelos-base genéricos e editáveis, na estrutura da skill de contratos da Guria** | Dar ponto de partida sem presumir validade | Texto com `[CAMPO A PREENCHER]` em tudo que depende de negociação/jurídico; aviso permanente de revisão profissional. |
| 15 | **Aceite de proposta ≠ assinatura certificada** | Não inventar validade legal | Texto/UX devem manter "registro de aceite"; assinatura real só via provedor (P1/P3). |
