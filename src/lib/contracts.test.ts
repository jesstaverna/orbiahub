import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { LEGAL_NOTICE, VARIABLES, contractError, daysToEnd, findPlaceholders, sectionsFromForm } from './contracts';

const sql = readFileSync('supabase/migrations/20261116000010_contracts.sql', 'utf8');

describe('contratos', () => {
  it('as variáveis do app são exatamente as que o SQL resolve (contract_generate)', () => {
    const gen = sql.slice(sql.indexOf('v_vars := jsonb_build_object('), sql.indexOf("'data.hoje'"));
    const dbKeys = [...gen.matchAll(/'([a-z_]+\.[a-z_]+)',/g)].map((m) => m[1]);
    expect([...dbKeys, 'data.hoje'].sort()).toEqual(VARIABLES.map((v) => v.key).sort());
  });
  it('toda variável usada nos modelos-base existe', () => {
    const seed = sql.slice(sql.indexOf('create or replace function app.seed_contracts'));
    const used = new Set([...seed.matchAll(/\{\{([^}]+)\}\}/g)].map((m) => m[1]));
    for (const u of used) expect(VARIABLES.map((v) => v.key), u).toContain(u);
  });
  it('detecta lacunas que bloqueiam a aprovação', () => {
    const r = findPlaceholders([{ title: 'A', body: 'Cliente {{cliente.nome}} paga [CAMPO A PREENCHER — valor] e [CAMPO A PREENCHER]' }, { title: 'B', body: '{{x.y}}' }]);
    expect(r.blanks).toBe(2);
    expect(r.variables).toEqual(['cliente.nome', 'x.y']);
    expect(findPlaceholders([{ title: 'ok', body: 'tudo preenchido' }])).toEqual({ variables: [], blanks: 0 });
  });
  it('monta seções do formulário descartando vazias', () => {
    expect(sectionsFromForm(['Objeto', '', ''], ['texto', '', 'sem título'])).toEqual([{ title: 'Objeto', body: 'texto' }, { title: 'Cláusula', body: 'sem título' }]);
  });
  it('calcula dias até o fim da vigência', () => {
    expect(daysToEnd('2027-07-09', '2027-07-01')).toBe(8);
    expect(daysToEnd('2027-06-30', '2027-07-01')).toBe(-1);
    expect(daysToEnd(null, '2027-07-01')).toBeNull();
  });
  it('mostra mensagens de regra de negócio e esconde erros técnicos', () => {
    expect(contractError({ code: '23514', message: 'Informe o motivo do cancelamento' })).toBe('Informe o motivo do cancelamento');
    expect(contractError({ code: '23514', message: 'new row violates check constraint "contracts_check"' })).toBe('Não foi possível concluir a operação.');
    expect(contractError({ code: '42501', message: 'new row violates row-level security policy' })).toBe('Seu perfil não tem permissão para esta ação.');
  });
  it('o aviso legal nega validade automática e assinatura pelo sistema', () => {
    expect(LEGAL_NOTICE).toMatch(/NÃO tem validade jurídica automática/);
    expect(LEGAL_NOTICE).toMatch(/não assina/);
  });
});
