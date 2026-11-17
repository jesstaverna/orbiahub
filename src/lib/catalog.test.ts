import { describe, expect, it } from 'vitest';
import { CATEGORIES, packageTotals, parseBRL, splitLines } from './catalog';

describe('catálogo', () => {
  it('converte valores em reais no formato brasileiro', () => {
    expect(parseBRL('1.500,50')).toBe(1500.5);
    expect(parseBRL('2000')).toBe(2000);
    expect(parseBRL('')).toBe(0);
    expect(parseBRL('abc')).toBe(0);
    expect(parseBRL(null)).toBe(0);
  });
  it('lista de entregáveis: uma por linha, sem vazias e limitada', () => {
    expect(splitLines(' 12 posts/mês \n\n 4 stories \n')).toEqual(['12 posts/mês', '4 stories']);
    expect(splitLines(Array.from({ length: 50 }, (_, i) => `item ${i}`).join('\n'))).toHaveLength(30);
  });
  it('totais do pacote separam pontual e mensal (mesmo cenário do teste SQL)', () => {
    expect(packageTotals([{ billing: 'mensal', quantity: 1, price: 2000 }, { billing: 'pontual', quantity: 1, price: 1000 }])).toEqual({ oneTime: 1000, monthly: 2000 });
    expect(packageTotals([{ billing: 'mensal', quantity: 0.5, price: 333.33 }]).monthly).toBe(166.67);
    expect(packageTotals([])).toEqual({ oneTime: 0, monthly: 0 });
  });
  it('categorias batem com o CHECK do banco', () => {
    const sql = (require('node:fs') as typeof import('node:fs')).readFileSync('supabase/migrations/20261116000009_service_catalog.sql', 'utf8');
    const m = sql.match(/category in \(([^)]*)\)/)![1];
    expect([...m.matchAll(/'([a-z_]+)'/g)].map((x) => x[1]).sort()).toEqual([...CATEGORIES].sort());
  });
});
