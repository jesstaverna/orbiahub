import Link from 'next/link';
import { requireModule } from '@/lib/session';
import { PageHeader, Field, Empty } from '@/components/ui';
import { SubmitButton } from '@/components/SubmitButton';
import { CLAUSE_CATEGORY_LABEL, LEGAL_NOTICE, SERVICE_TYPE_LABEL, VARIABLES } from '@/lib/contracts';
import { addTemplateClause, deleteClause, deleteTemplate, duplicateTemplate, moveTemplateClause, removeTemplateClause, saveClause, saveTemplate, toggleClause, toggleTemplate } from './actions';

export const metadata = { title: 'Modelos de contrato' };

type Clause = { id: string; title: string; category: string; body: string; is_starter: boolean; active: boolean };

export default async function Modelos({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { supabase, can } = await requireModule('contratos');
  const manage = can('contracts.templates');
  const tab = (await searchParams).tab === 'clausulas' ? 'clausulas' : 'modelos';
  const [{ data: tpls }, { data: cls }, { data: links }] = await Promise.all([
    supabase.from('contract_templates').select('*').order('active', { ascending: false }).order('name'),
    supabase.from('clause_library').select('*').order('category').order('title'),
    supabase.from('contract_template_clauses').select('id, template_id, clause_id, position').order('position'),
  ]);
  const clauses = (cls ?? []) as Clause[];
  const byId = new Map(clauses.map((c) => [c.id, c]));

  return (
    <>
      <PageHeader title="Modelos e cláusulas" subtitle="Biblioteca editável por agência. Contratos já gerados guardam uma cópia e não mudam quando você edita aqui."
        actions={<><Link href="/contratos" className="btn">← Contratos</Link><Link href="/contratos/modelos" className={`btn ${tab === 'modelos' ? 'btn-dark' : ''}`}>Modelos ({tpls?.length ?? 0})</Link><Link href="/contratos/modelos?tab=clausulas" className={`btn ${tab === 'clausulas' ? 'btn-dark' : ''}`}>Cláusulas ({clauses.length})</Link></>} />
      <p className="mb-6 max-w-3xl rounded-xl border border-line bg-subtle p-4 text-sm" role="note">{LEGAL_NOTICE} Os modelos e cláusulas <b>starter</b> são pontos de partida genéricos, com lacunas <code>[CAMPO A PREENCHER]</code> — o sistema bloqueia a aprovação enquanto elas existirem.</p>

      {tab === 'modelos' ? (
        <>
          {!tpls?.length && <Empty title="Nenhum modelo" text={manage ? 'Crie um modelo e escolha as cláusulas que o compõem.' : 'Nenhum modelo cadastrado.'} />}
          <div className="space-y-3">{tpls?.map((t) => {
            const items = (links ?? []).filter((l) => l.template_id === t.id);
            return (
              <details key={t.id} className={`card ${t.active ? '' : 'opacity-60'}`}>
                <summary className="flex cursor-pointer flex-wrap items-center gap-3 text-sm"><span className="font-medium">{t.name}</span><span className="badge">{SERVICE_TYPE_LABEL[t.service_type]}</span>
                  {t.is_starter && <span className="badge">modelo-base</span>}{!t.active && <span className="badge">inativo</span>}<span className="ml-auto text-xs text-muted">{items.length} cláusulas</span></summary>
                <div className="mt-5 space-y-4">
                  {t.description && <p className="text-sm text-muted">{t.description}</p>}
                  <ol className="divide-y divide-line text-sm">{items.map((l, i) => (
                    <li key={l.id} className="flex flex-wrap items-center justify-between gap-2 py-2"><span>{i + 1}. {byId.get(l.clause_id)?.title ?? 'Cláusula'}{byId.get(l.clause_id)?.active === false && <span className="badge ml-2">inativa</span>}</span>
                      {manage && <span className="flex gap-1.5">
                        <form action={moveTemplateClause.bind(null, t.id, l.id, 'up')}><button className="btn btn-sm" aria-label="Subir" disabled={i === 0}>↑</button></form>
                        <form action={moveTemplateClause.bind(null, t.id, l.id, 'down')}><button className="btn btn-sm" aria-label="Descer" disabled={i === items.length - 1}>↓</button></form>
                        <form action={removeTemplateClause.bind(null, l.id)}><button className="btn btn-sm text-danger">Remover</button></form></span>}</li>))}
                    {!items.length && <li className="py-2 text-muted">Modelo sem cláusulas.</li>}</ol>
                  {manage && <>
                    <form action={addTemplateClause.bind(null, t.id)} className="flex flex-wrap items-end gap-2 border-t border-line pt-4">
                      <Field label="Adicionar cláusula"><select name="clause" required defaultValue="" className="input min-w-64"><option value="" disabled>Escolha…</option>{clauses.filter((c) => c.active && !items.some((l) => l.clause_id === c.id)).map((c) => <option key={c.id} value={c.id}>{c.title}</option>)}</select></Field>
                      <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Adicionar</SubmitButton></form>
                    <form action={saveTemplate.bind(null, t.id)} className="grid items-end gap-2 sm:grid-cols-[1fr_10rem_2fr_auto]">
                      <Field label="Nome"><input name="name" defaultValue={t.name} className="input" /></Field>
                      <Field label="Serviço"><select name="service_type" defaultValue={t.service_type} className="input">{Object.entries(SERVICE_TYPE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
                      <Field label="Descrição"><input name="description" defaultValue={t.description ?? ''} className="input" /></Field><SubmitButton className="btn btn-sm" pendingText="…">Salvar</SubmitButton></form>
                    <div className="flex flex-wrap gap-2">
                      <form action={duplicateTemplate.bind(null, t.id)}><button className="btn btn-sm">Duplicar</button></form>
                      <form action={toggleTemplate.bind(null, t.id, !t.active)}><button className="btn btn-sm">{t.active ? 'Desativar' : 'Reativar'}</button></form>
                      <form action={deleteTemplate.bind(null, t.id)}><button className="btn btn-sm btn-danger">Excluir</button></form></div></>}
                </div>
              </details>); })}</div>
          {manage && <form action={saveTemplate.bind(null, null)} className="card mt-6 grid items-end gap-3 sm:grid-cols-[1fr_10rem_2fr_auto]"><Field label="Novo modelo"><input name="name" required className="input" /></Field>
            <Field label="Serviço"><select name="service_type" defaultValue="geral" className="input">{Object.entries(SERVICE_TYPE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field label="Descrição"><input name="description" className="input" /></Field><SubmitButton className="btn btn-sm btn-dark" pendingText="…">Criar modelo</SubmitButton></form>}
        </>
      ) : (
        <>
          <div className="space-y-3">{clauses.map((c) => (
            <details key={c.id} className={`card ${c.active ? '' : 'opacity-60'}`}>
              <summary className="flex cursor-pointer flex-wrap items-center gap-3 text-sm"><span className="font-medium">{c.title}</span><span className="badge">{CLAUSE_CATEGORY_LABEL[c.category]}</span>{c.is_starter && <span className="badge">modelo-base</span>}{!c.active && <span className="badge">inativa</span>}</summary>
              {manage ? (
                <div className="mt-4 space-y-3">
                  <form action={saveClause.bind(null, c.id)} className="space-y-3">
                    <div className="grid gap-3 sm:grid-cols-[2fr_1fr]"><Field label="Título"><input name="title" defaultValue={c.title} className="input" /></Field>
                      <Field label="Categoria"><select name="category" defaultValue={c.category} className="input">{Object.entries(CLAUSE_CATEGORY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
                    <Field label="Texto"><textarea name="body" defaultValue={c.body} rows={Math.min(Math.max(c.body.split('\n').length + 2, 4), 14)} className="input font-mono text-[13px]" /></Field>
                    <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Salvar cláusula</SubmitButton></form>
                  <div className="flex gap-2"><form action={toggleClause.bind(null, c.id, !c.active)}><button className="btn btn-sm">{c.active ? 'Desativar' : 'Reativar'}</button></form><form action={deleteClause.bind(null, c.id)}><button className="btn btn-sm btn-danger">Excluir</button></form></div>
                </div>) : <p className="mt-3 whitespace-pre-line text-sm text-muted">{c.body}</p>}
            </details>))}</div>
          {manage && <form action={saveClause.bind(null, null)} className="card mt-6 space-y-3"><h2 className="text-base font-semibold">Nova cláusula</h2>
            <div className="grid gap-3 sm:grid-cols-[2fr_1fr]"><Field label="Título"><input name="title" required className="input" /></Field><Field label="Categoria"><select name="category" defaultValue="geral" className="input">{Object.entries(CLAUSE_CATEGORY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
            <Field label="Texto" hint={`Variáveis: ${VARIABLES.map((v) => `{{${v.key}}}`).join('  ')}`}><textarea name="body" required rows={5} className="input font-mono text-[13px]" /></Field>
            <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Criar cláusula</SubmitButton></form>}
        </>
      )}
    </>
  );
}
