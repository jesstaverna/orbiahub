/** Contratos: rótulos e funções puras (testadas). A fonte da verdade das regras é o banco (migração 0010). */
export const STATUS: Record<string, { label: string; tone: string }> = {
  rascunho: { label: 'Rascunho', tone: 'border-line' },
  em_revisao: { label: 'Em revisão', tone: 'border-warn text-warn' },
  aguardando_assinatura: { label: 'Aguardando assinatura', tone: 'border-brand text-brand' },
  assinado: { label: 'Assinado (registro manual)', tone: 'border-ok text-ok' },
  encerrado: { label: 'Encerrado', tone: 'border-line text-muted' },
  cancelado: { label: 'Cancelado', tone: 'border-danger text-danger' },
};
export const EDITABLE = ['rascunho', 'em_revisao'];
export const TYPE_LABEL: Record<string, string> = { recorrente: 'Recorrente (mensal)', pontual: 'Projeto pontual' };
export const EVENT_LABEL: Record<string, string> = {
  criado: 'Criado', rascunho: 'Voltou para rascunho', em_revisao: 'Enviado para revisão', aguardando_assinatura: 'Aprovado e enviado para assinatura',
  assinado: 'Assinatura registrada', encerrado: 'Encerrado', cancelado: 'Cancelado', renovado: 'Renovado', versao: 'Versão salva', nota: 'Nota',
};
export const SERVICE_TYPE_LABEL: Record<string, string> = {
  social_media: 'Social media', trafego_pago: 'Tráfego pago', branding: 'Branding', site: 'Site', landing_page: 'Landing page', design: 'Design', consultoria: 'Consultoria', geral: 'Geral',
};
export const CLAUSE_CATEGORY_LABEL: Record<string, string> = {
  partes: 'Partes', escopo: 'Escopo', prazos: 'Prazos', obrigacoes: 'Obrigações', revisoes: 'Revisões', pagamento: 'Pagamento', propriedade: 'Propriedade intelectual', ia: 'Uso de IA',
  confidencialidade: 'Confidencialidade e LGPD', vigencia: 'Vigência e rescisão', responsabilidade: 'Responsabilidade', foro: 'Foro', servico: 'Específica do serviço', geral: 'Geral',
};

export const LEGAL_NOTICE =
  'Modelo-base editável. Este documento NÃO tem validade jurídica automática e deve ser revisado por profissional habilitado antes de ser enviado para assinatura. O orbiahub. não assina contratos.';

/** Variáveis disponíveis nas cláusulas — espelham exatamente as que contract_generate (SQL) resolve. */
export const VARIABLES: { key: string; label: string }[] = [
  { key: 'cliente.nome', label: 'Nome do cliente' }, { key: 'cliente.razao_social', label: 'Razão social' }, { key: 'cliente.documento', label: 'CPF/CNPJ do cliente' },
  { key: 'cliente.endereco', label: 'Endereço do cliente' }, { key: 'cliente.email', label: 'E-mail do cliente' }, { key: 'cliente.telefone', label: 'Telefone do cliente' },
  { key: 'agencia.nome', label: 'Nome da agência' },
  { key: 'contrato.numero', label: 'Número do contrato' }, { key: 'contrato.titulo', label: 'Título' }, { key: 'contrato.tipo', label: 'Tipo (recorrente/pontual)' },
  { key: 'contrato.inicio', label: 'Data de início' }, { key: 'contrato.fim', label: 'Data de término' }, { key: 'contrato.vigencia_meses', label: 'Vigência em meses' },
  { key: 'contrato.valor_mensal', label: 'Valor mensal' }, { key: 'contrato.valor_pontual', label: 'Valor pontual' }, { key: 'contrato.valor_total', label: 'Valor total' },
  { key: 'contrato.forma_pagamento', label: 'Forma de pagamento' }, { key: 'contrato.parcelas', label: 'Parcelas' }, { key: 'contrato.aviso_renovacao_dias', label: 'Aviso de renovação (dias)' },
  { key: 'proposta.numero', label: 'Nº da proposta' }, { key: 'servicos.lista', label: 'Lista de serviços e entregáveis' }, { key: 'data.hoje', label: 'Data de hoje' },
];

export interface Section { title: string; body: string }

/** Lacunas que bloqueiam a aprovação: {{variável}} não resolvida e [CAMPO A PREENCHER…]. */
export function findPlaceholders(sections: Section[]): { variables: string[]; blanks: number } {
  const text = sections.map((s) => `${s.title}\n${s.body}`).join('\n');
  const variables = [...new Set([...text.matchAll(/\{\{\s*([^}]+?)\s*\}\}/g)].map((m) => m[1]))];
  const blanks = (text.match(/\[CAMPO A PREENCHER/g) ?? []).length;
  return { variables, blanks };
}

export function sectionsFromForm(titles: string[], bodies: string[]): Section[] {
  return titles.map((t, i) => ({ title: t.trim(), body: (bodies[i] ?? '').trim() })).filter((s) => s.title || s.body).map((s) => ({ title: s.title || 'Cláusula', body: s.body }));
}

/** Dias até o fim da vigência (negativo = vencido); null se não há data. */
export function daysToEnd(end: string | null | undefined, today: string): number | null {
  if (!end) return null;
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86_400_000);
}

/** Mensagem segura para o usuário: usa a do banco só quando é uma regra de negócio nossa (já em português). */
export function contractError(error: { code?: string; message?: string }, fallback = 'Não foi possível concluir a operação.'): string {
  const m = error.message ?? '';
  if (['23514', '42501', '22023', '23505'].includes(error.code ?? '') && !/violates|policy|permission denied|duplicate key|row-level/i.test(m)) return m;
  if (error.code === '23505') return 'Esta proposta já tem um contrato ativo.';
  if (error.code === '42501') return 'Seu perfil não tem permissão para esta ação.';
  return fallback;
}
