/** Catálogo de serviços: rótulos e funções puras (testadas). Os preços são sempre da agência — nada é pré-cadastrado. */
export const CATEGORY_LABEL: Record<string, string> = {
  social_media: 'Social media', trafego_pago: 'Tráfego pago', branding: 'Branding', site: 'Sites',
  landing_page: 'Landing pages', design: 'Design', consultoria: 'Consultoria', outro: 'Outro',
};
export const CATEGORIES = Object.keys(CATEGORY_LABEL);

/** "1.500,50" → 1500.5 ; inválido → 0. */
export const parseBRL = (v: FormDataEntryValue | string | null | undefined) =>
  Number(String(v ?? '0').trim().replace(/\./g, '').replace(',', '.')) || 0;

/** Texto com uma linha por item → lista (sem linhas vazias, no máximo 30). */
export const splitLines = (v: FormDataEntryValue | string | null | undefined) =>
  String(v ?? '').split('\n').map((s) => s.trim()).filter(Boolean).slice(0, 30);

export interface PackageLine { billing: 'pontual' | 'mensal'; quantity: number; price: number }
/** Totais de um pacote: pontual (uma vez) e mensal (por mês). */
export function packageTotals(lines: PackageLine[]) {
  const sum = (b: PackageLine['billing']) => Math.round(lines.filter((l) => l.billing === b).reduce((s, l) => s + l.quantity * l.price, 0) * 100) / 100;
  return { oneTime: sum('pontual'), monthly: sum('mensal') };
}
