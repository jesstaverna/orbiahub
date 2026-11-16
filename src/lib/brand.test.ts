import { describe, expect, it } from 'vitest';
import { brandVars, hexToRgb, isHexColor, luminance } from './brand';

describe('identidade visual da agência', () => {
  it('só aceita cores #RRGGBB (nada de CSS arbitrário vindo do banco)', () => {
    expect(isHexColor('#DCEA1E')).toBe(true);
    expect(isHexColor('red')).toBe(false);
    expect(isHexColor('#fff')).toBe(false);
    expect(isHexColor('#12345; background:url(x)')).toBe(false);
    expect(isHexColor(undefined)).toBe(false);
    expect(brandVars('javascript:alert(1)')).toBeUndefined();
  });
  it('gera variáveis CSS com tom escuro para hover', () => {
    expect(hexToRgb('#DCEA1E')).toEqual([220, 234, 30]);
    expect(brandVars('#FF0000')).toMatchObject({ '--brand': '255 0 0', '--brand-dark': '217 0 0' });
  });
  it('escolhe texto com contraste: claro sobre cor escura, escuro sobre cor clara', () => {
    expect(brandVars('#DCEA1E')?.['--on-brand']).toBe('0 0 0');
    expect(brandVars('#0B1F44')?.['--on-brand']).toBe('255 255 255');
    expect(luminance([255, 255, 255])).toBeCloseTo(1, 5);
  });
});
