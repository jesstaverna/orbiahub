import { describe, expect, it } from 'vitest';
import { mfaNextStep, mfaPath } from './mfa';
import { validatePassword } from './password';

describe('MFA', () => {
  const base = { privileged: true, current: 'aal1', next: 'aal1', required: false };
  it('sem política e sem fator: não exige nada', () => { expect(mfaNextStep(base)).toBeNull(); });
  it('com fator verificado e sessão aal1: pede o código', () => { expect(mfaNextStep({ ...base, next: 'aal2' })).toBe('challenge'); });
  it('já em aal2: libera', () => { expect(mfaNextStep({ ...base, current: 'aal2', next: 'aal2' })).toBeNull(); });
  it('política ativa: admin sem fator precisa cadastrar', () => { expect(mfaNextStep({ ...base, required: true })).toBe('enroll'); });
  it('política ativa não obriga quem não é privilegiado', () => { expect(mfaNextStep({ ...base, privileged: false, required: true })).toBeNull(); });
  it('mapeia para rotas', () => { expect(mfaPath('challenge')).toBe('/mfa'); expect(mfaPath('enroll')).toContain('/seguranca'); expect(mfaPath(null)).toBeNull(); });
});

describe('política de senha', () => {
  it('aceita senha forte', () => { expect(validatePassword('Orbita2026Hub', 'Orbita2026Hub')).toBeNull(); });
  it('recusa curta, sem número/letra, previsível e divergente', () => {
    expect(validatePassword('abc123')).toMatch(/10 caracteres/);
    expect(validatePassword('somenteletras')).toMatch(/letras e números/);
    expect(validatePassword('12345678901')).toMatch(/letras e números/);
    expect(validatePassword('senha12345')).toMatch(/previsível/);
    expect(validatePassword('aaaaaaaaaaaa')).toMatch(/letras e números|previsível/);
    expect(validatePassword('Orbita2026Hub', 'outra')).toMatch(/não conferem/);
  });
});
