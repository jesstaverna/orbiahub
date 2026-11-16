/** Identidade visual por agência: a cor de destaque da agência vira variáveis CSS (ver tailwind.config.ts e globals.css). */
export const HEX_COLOR = /^#[0-9a-fA-F]{6}$/;

export function isHexColor(v: unknown): v is string {
  return typeof v === 'string' && HEX_COLOR.test(v);
}

export function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

/** Luminância relativa WCAG (0 = preto, 1 = branco). */
export function luminance([r, g, b]: [number, number, number]): number {
  const f = (c: number) => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}

/**
 * Variáveis CSS que sobrescrevem a cor de destaque. Valor inválido/ausente → undefined (usa o padrão do orbiahub).
 * O texto sobre a cor (--on-brand) é preto ou branco conforme o contraste, para qualquer cor escolhida pela agência.
 */
export function brandVars(primary: unknown): Record<string, string> | undefined {
  if (!isHexColor(primary)) return undefined;
  const rgb = hexToRgb(primary);
  const dark = rgb.map((c) => Math.round(c * 0.85));
  const on = luminance(rgb) > 0.4 ? '0 0 0' : '255 255 255';
  return { '--brand': rgb.join(' '), '--brand-dark': dark.join(' '), '--on-brand': on };
}
