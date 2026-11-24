# Marketing OS — roadmap OrbiaHub
2026-11-24. Proprietária: Guria do Design. Muvens: primeira agência piloto. Não reutilizar bancos de outros produtos.

## Referências
- Metrik Social Mídia IA: https://metriksales.com/socialmedia-ia/ — vídeo, copy por canal, agendamento, publicação, resposta por palavra-chave.
- ManyChat: https://help.manychat.com/en/articles/17741897-instagram-post-and-reel-comments-trigger — gatilhos e fluxos, respeitar regras da API.
- Metricool: https://help.metricool.com/pt/como-enviar-publicacoes-para-revisao-com-o-sistema-de-aprovacao-do-metricool-yvdr0 — aprovação e revisão.
- mLabs: https://ajuda.mlabs.com.br/pt-BR/articles/4645839-como-usar-a-opcao-enviar-para-aprovacao-da-mlabs — aprovação externa.
- Runrun.it e Trello: tarefas, kanban, responsáveis, calendário e acompanhamento de produção.

## Sequência de entrega
| Prioridade | Escopo | Critério de aceite |
|---|---|---|
| P0 | Ambiente dedicado, CI, Auth/MFA, migrations, RLS, backups, observabilidade | banco descartável validado; build e testes verdes; nenhuma regressão; ambiente preview separado |
| P1 | Marcas/Brand Center, projetos/tarefas, calendário editorial, conteúdo manual, feed visual | criar marca, vincular cliente, planejar conteúdo real, filtrar por marca, editar rascunho e ordenar peças |
| P2 | Aprovação interna e portal cliente, mídia privada, Content Studio IA | cliente só vê itens autorizados; versões imutáveis; aprovação invalidada por edição; geração medida por consumo |
| P3 | OAuth de redes, publicação agendada, analytics | Instagram/Facebook primeiro; depois demais redes conforme suporte oficial; idempotência, retries, DLQ e logs; publicação confirmada pelo provedor |
| P4 | Comentários/directs, editor visual de fluxos, inbox, CRM | webhook assinado; deduplicação; palavras-chave; consentimento, opt-out, janela de mensagens, atribuição humana; lead sem duplicidade |
| P5 | Gestão de anúncios e relatórios | leitura Meta/Google; métricas com data e origem; alterações de orçamento/campanha exigem confirmação |
| P6 | Video Studio e agentes de marketing/atendimento | jobs assíncronos de transcrição/cortes/legendas; aprovação humana; contexto por marca e trilha de auditoria |
| P7 | Assinaturas, franquias e custos de API | cobrança sandbox, webhooks assinados, ledger imutável, cotas e reservas atômicas; sem excedente não autorizado |

Controles mínimos de uso e orçamento entram antes de qualquer chamada paga de IA, não apenas em P7. Contratos, financeiro e CRM existentes continuam; projetos e portal planejados na arquitetura anterior não são descartados.

## Arquitetura alvo
agencies -> marketing_brands -> content_items / social_accounts / automation_flows / conversations / ad_accounts
clients -> marketing_brands (opcional, vínculo no mesmo tenant).
Conteúdo: rascunho -> revisão interna -> aprovação cliente -> aprovado -> agendado -> publicado / falha. Status externo depende da API.
Jobs existentes para tarefas assíncronas; provedores separados por adaptadores no servidor; tokens nunca no browser ou logs; webhooks autenticados com validação de replay; storage privado por agência/marca. UTC para execução, timezone da marca para apresentação.
Agentes sem ferramentas de escrita irrestrita; IA nunca publica sem política/autorização explícita. LGPD: minimização, retenção, consentimento quando necessário, exclusão/exportação e registro de subprocessadores.
UI: tokens e temas existentes, lilás e rosa como acentos; não trocar identidade das telas já existentes. Testes mobile/desktop e acessibilidade.

## Estado desta branch
- Schema candidato em supabase/migration-drafts/marketing_brands.sql; ainda não aplicado e não é migration automática.
- /brand: CRUD parcial (criar/editar/arquivar/reativar), usando sessão do usuário e RLS. Escrita restrita a settings.manage + brand.access; leitura a brand.access e app.access.
- Sem conexão de redes, geração de IA ou dados simulados.
- Staging Supabase bloqueado por limite de dois projetos gratuitos da conta Guria do Design. Não pausar/deletar/reutilizar Prospecta ou Prompt Club. Vercel isolado só depois de definir banco e credenciais.
- Antes de merge: revisar migração, executar testes de tenant, conferir CI e testar navegador e Auth real. Não fazer deploy de produção a partir desta branch.
