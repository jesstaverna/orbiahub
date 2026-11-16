import { describe, expect, it, vi } from 'vitest';
vi.mock('server-only', () => ({}));
vi.mock('next/headers', () => ({ headers: async () => new Headers() }));
const { firstIp } = await import('./ip');

describe('IP do visitante', () => {
  it('pega o primeiro da lista x-forwarded-for', () => { expect(firstIp('203.0.113.9, 10.0.0.1')).toBe('203.0.113.9'); });
  it('aceita IPv6', () => { expect(firstIp('2001:db8::1')).toBe('2001:db8::1'); });
  it('rejeita lixo e injeção (vai ao banco como evidência)', () => {
    expect(firstIp("1.2.3.4'; drop table x;--")).toBeNull();
    expect(firstIp('')).toBeNull();
    expect(firstIp(null)).toBeNull();
    expect(firstIp('<script>')).toBeNull();
  });
});
