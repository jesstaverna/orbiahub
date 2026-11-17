/** Chave do papel (profiles.role). Os papéis de sistema têm chaves fixas; agências criam outros. O significado vem da tabela `roles`. */
export type Role = string;

export const SYSTEM_ROLES = ['admin', 'gestor', 'comercial', 'financeiro', 'designer', 'trafego', 'cliente'] as const;
/** Papéis cujas permissões são fixas no banco. */
export const LOCKED_ROLES = ['admin', 'cliente'];

/** Catálogo de permissões (espelha app.all_permissions() no banco). Agrupado para a tela de papéis. */
export const PERMISSIONS: { key: string; label: string; group: string }[] = [
  { key: 'app.access', label: 'Entrar no sistema (equipe)', group: 'Geral' },
  { key: 'clients.read', label: 'Ver clientes e contatos', group: 'Clientes' },
  { key: 'clients.write', label: 'Criar e editar clientes e contatos', group: 'Clientes' },
  { key: 'clientservices.read', label: 'Ver serviços contratados e valores', group: 'Clientes' },
  { key: 'clientservices.write', label: 'Editar serviços contratados', group: 'Clientes' },
  { key: 'crm.access', label: 'CRM: leads, interações e lembretes', group: 'Comercial' },
  { key: 'pipeline.manage', label: 'Configurar etapas do funil', group: 'Comercial' },
  { key: 'proposals.read', label: 'Ver propostas', group: 'Comercial' },
  { key: 'proposals.write', label: 'Criar e editar propostas', group: 'Comercial' },
  { key: 'proposals.discount', label: 'Autorizar desconto em propostas', group: 'Comercial' },
  { key: 'catalog.read', label: 'Ver catálogo de serviços e pacotes', group: 'Comercial' },
  { key: 'catalog.manage', label: 'Gerenciar catálogo (serviços, preços, pacotes)', group: 'Comercial' },
  { key: 'finance.access', label: 'Financeiro: lançamentos, recorrências, ativar proposta', group: 'Financeiro' },
  { key: 'goals.read', label: 'Ver metas e resultados', group: 'Financeiro' },
  { key: 'goals.manage', label: 'Definir metas', group: 'Financeiro' },
  { key: 'brand.access', label: 'Brand Center / identidade dos clientes', group: 'Módulos' },
  { key: 'ads.access', label: 'Tráfego pago e anúncios', group: 'Módulos' },
  { key: 'reports.access', label: 'Relatórios', group: 'Módulos' },
  { key: 'ai.access', label: 'Agentes de IA', group: 'Módulos' },
  { key: 'automations.read', label: 'Ver fila de automações', group: 'Administração' },
  { key: 'audit.read', label: 'Ver auditoria', group: 'Administração' },
  { key: 'settings.manage', label: 'Gerenciar usuários, papéis e a agência', group: 'Administração' },
];
export const PERMISSION_KEYS = PERMISSIONS.map((p) => p.key);

export type ModuleKey =
  | 'dashboard' | 'crm' | 'catalogo' | 'atendimento-ia' | 'propostas' | 'contratos' | 'clientes' | 'brand' | 'projetos'
  | 'calendario' | 'trafego' | 'financeiro' | 'metas' | 'relatorios' | 'ia' | 'portal' | 'automacoes' | 'configuracoes';

export interface ModuleDef {
  key: ModuleKey;
  label: string;
  href: string;
  /** Permissão exigida para ver o módulo (a RLS no banco é quem realmente protege os dados). */
  permission: string;
  /** 1 = implementado nesta entrega; 2..4 = fase planejada (página honesta de "em construção") */
  phase: 1 | 2 | 3 | 4;
  icon: string;
  summary: string;
  planned?: string[];
}

export const MODULES: ModuleDef[] = [
  { key: 'dashboard', label: 'Dashboard', href: '/dashboard', permission: 'app.access', phase: 1, icon: 'layout-dashboard', summary: 'Visão executiva com dados reais.' },
  { key: 'crm', label: 'CRM e Leads', href: '/crm', permission: 'crm.access', phase: 1, icon: 'kanban', summary: 'Funil, leads e follow-ups.' },
  { key: 'atendimento-ia', label: 'Atendimento com IA', href: '/atendimento-ia', permission: 'crm.access', phase: 3, icon: 'message-circle', summary: 'Agente de IA de atendimento comercial via RD Conversas.',
    planned: ['Indicadores: leads atendidos pela IA, qualificados, transferidos, propostas originadas, conversões, faturamento atribuído', 'Regras de transferência para humano', 'Respeito à janela de 24h e templates do WhatsApp', 'Registro automático no CRM'] },
  { key: 'propostas', label: 'Propostas Comerciais', href: '/propostas', permission: 'proposals.read', phase: 1, icon: 'file-text', summary: 'Propostas online com link exclusivo e aceite.' },
  { key: 'contratos', label: 'Contratos', href: '/contratos', permission: 'proposals.read', phase: 2, icon: 'file-signature', summary: 'Contratos gerados a partir das propostas aceitas.',
    planned: ['Modelos por serviço com preenchimento automático', 'Rascunho com revisão humana obrigatória', 'Assinatura via Clicksign/ZapSign (integração pendente)', 'Alertas de vencimento, renovação e reajuste'] },
  { key: 'catalogo', label: 'Catálogo de Serviços', href: '/catalogo', permission: 'catalog.read', phase: 1, icon: 'package', summary: 'Serviços, preços e pacotes que alimentam as propostas.' },
  { key: 'clientes', label: 'Clientes', href: '/clientes', permission: 'clients.read', phase: 1, icon: 'users', summary: 'Cadastro e visão 360° de cada cliente.' },
  { key: 'brand', label: 'Brand Center / KV', href: '/brand', permission: 'brand.access', phase: 2, icon: 'palette', summary: 'Biblioteca de identidade visual por cliente.',
    planned: ['Logos, paletas, tipografias, KV, brandbooks', 'Armazenamento privado com download autorizado', 'Regras de design e tom de voz (base de conhecimento para a IA)'] },
  { key: 'projetos', label: 'Projetos e Tarefas', href: '/projetos', permission: 'app.access', phase: 2, icon: 'list-checks', summary: 'Kanban, lista e controle de entregáveis.',
    planned: ['Tarefas com checklist, arquivos, comentários e horas', 'Controle de entregáveis contratados (ex.: 12 posts/mês)', 'Fluxo de aprovação e escopo extra'] },
  { key: 'calendario', label: 'Calendário de Produção', href: '/calendario', permission: 'app.access', phase: 2, icon: 'calendar', summary: 'Prazos e entregas de produção.', planned: ['Calendário de entregas por cliente e responsável'] },
  { key: 'trafego', label: 'Tráfego Pago', href: '/trafego', permission: 'ads.access', phase: 3, icon: 'bar-chart-3', summary: 'Meta Ads e Google Ads por cliente.',
    planned: ['Investimento, CTR, CPC, CPM, CPL, ROAS', 'Alertas de custo por lead e orçamento', 'Relatórios compartilháveis', 'Integrações pendentes: contas e tokens Meta/Google'] },
  { key: 'financeiro', label: 'Financeiro', href: '/financeiro', permission: 'finance.access', phase: 1, icon: 'wallet', summary: 'Entradas, saídas, recorrências e previsão.' },
  { key: 'metas', label: 'Metas e Resultados', href: '/metas', permission: 'goals.read', phase: 1, icon: 'target', summary: 'Metas mensais/anuais e projeções.' },
  { key: 'relatorios', label: 'Relatórios', href: '/relatorios', permission: 'reports.access', phase: 4, icon: 'file-bar-chart', summary: 'Relatórios gerenciais e de clientes.', planned: ['Relatórios financeiros, comerciais e de performance exportáveis'] },
  { key: 'ia', label: 'Inteligência Artificial', href: '/ia', permission: 'ai.access', phase: 4, icon: 'sparkles', summary: 'Agentes de IA com contexto autorizado da agência.',
    planned: ['Perguntas em linguagem natural sobre dados reais (RLS do usuário)', 'Resumo diário automático', 'Rascunhos de proposta — sem ações críticas sem autorização'] },
  { key: 'portal', label: 'Portal do Cliente', href: '/portal', permission: 'settings.manage', phase: 2, icon: 'door-open', summary: 'Área externa com login individual.', planned: ['Aprovação de peças, briefings, documentos, relatórios'] },
  { key: 'automacoes', label: 'Automações', href: '/automacoes', permission: 'automations.read', phase: 1, icon: 'workflow', summary: 'Fila de processamento, logs e retentativas.' },
  { key: 'configuracoes', label: 'Configurações', href: '/configuracoes', permission: 'settings.manage', phase: 1, icon: 'settings', summary: 'Usuários, funil e integrações.' },
];

export function canAccess(permissions: string[] | null | undefined, key: ModuleKey) {
  const m = MODULES.find((x) => x.key === key);
  return !!m && !!permissions?.includes(m.permission);
}
