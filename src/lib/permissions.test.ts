import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { LOCKED_ROLES, MODULES, PERMISSION_KEYS, SYSTEM_ROLES, canAccess } from './permissions';

describe('permissões', () => {
  it('o catálogo do app é idêntico ao do banco (app.all_permissions na migração 0008)', () => {
    const sql = readFileSync('supabase/migrations/20261116000008_roles_permissions.sql', 'utf8');
    const block = sql.slice(sql.indexOf('select array['), sql.indexOf(']', sql.indexOf('select array[')));
    const db = [...block.matchAll(/'([a-z.]+)'/g)].map((m) => m[1]);
    expect([...db].sort()).toEqual([...PERMISSION_KEYS].sort());
  });
  it('todo módulo exige uma permissão que existe no catálogo', () => {
    for (const m of MODULES) expect(PERMISSION_KEYS, m.key).toContain(m.permission);
  });
  it('sem permissão não há acesso; com a permissão certa há', () => {
    expect(canAccess([], 'dashboard')).toBe(false);
    expect(canAccess(null, 'dashboard')).toBe(false);
    expect(canAccess(['app.access'], 'dashboard')).toBe(true);
    expect(canAccess(['app.access'], 'financeiro')).toBe(false);
    expect(canAccess(['finance.access'], 'financeiro')).toBe(true);
  });
  it('papéis de sistema incluem Gestor/Head; admin e cliente são fixos', () => {
    expect(SYSTEM_ROLES).toContain('gestor');
    expect(LOCKED_ROLES).toEqual(['admin', 'cliente']);
  });
});
