import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireModule } from '@/lib/session';
import { PageHeader, Field } from '@/components/ui';
import { SubmitButton } from '@/components/SubmitButton';
import { dateBR, dateTimeBR, money } from '@/lib/format';
import { todayBR } from '@/lib/domain';
import { EDITABLE, EVENT_LABEL, LEGAL_NOTICE, STATUS, TYPE_LABEL, VARIABLES, daysToEnd, findPlaceholders, type Section } from '@/lib/contracts';
import { approveContract, backToDraft, backToReview, cancelContract, closeContract, deleteDraft, registerSignature, renewContract, saveContract, saveSnapshot, sendToReview } from '../actions';

export const metadata = { title: 'Contrato' };

export default async function ContratoPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const { supabase, can } = await requireModule('contratos');
  const [{ data: c }, { data: events }, { data: versions }] = await Promise.all([
    supabase.from('contracts').select('*, clients(name)').eq('id', id).maybeSingle(),
    supabase.from('contract_events').select('id, kind, message, created_at').eq('contract_id', id).order('created_at', { ascending: false }).limit(50),
    supabase.from('contract_versions').select('id, version, note, created_at').eq('contract_id', id).order('version', { ascending: false }),
  ]);
  if (!c) notFound();

  const sections = (c.content ?? []) as Section[];
  const gaps = findPlaceholders(sections);
  const pending = gaps.blanks + gaps.variables.length;
  const editable = EDITABLE.includes(c.status) && can('contracts.write');
  const approver = can('contracts.approve');
  const writer = can('contracts.write');
  const days = c.status === 'assinado' ? daysToEnd(c.end_date, todayBR()) : null;
  const st = STATUS[c.status];

  return (
    <>
      <PageHeader title={`Contrato #${c.number}`} subtitle={`${c.clients?.name ?? 'Cliente'} · ${TYPE_LABEL[c.contract_type]}`}
        actions={<><span className={`badge ${st?.tone ?? ''}`}>{st?.label ?? c.status}</span><Link href={`/contratos/${id}/imprimir`} className="btn btn-sm" target="_blank">Versão para imprimir / PDF</Link></>} />

      <p className="mb-6 rounded-xl border border-line bg-subtle p-4 text-sm" role="note">{LEGAL_NOTICE}</p>
      {days != null && days <= c.renewal_notice_days && (
        <p className={`mb-6 rounded-xl border p-4 text-sm ${days < 0 ? 'border-danger text-danger' : 'border-warn text-warn'}`} role="alert">
          {days < 0 ? `A vigência terminou há ${-days} dia(s).` : `A vigência termina em ${days} dia(s).`} Renove ou encerre o contrato.</p>)}
      {c.status === 'cancelado' && c.cancelled_reason && <p className="mb-6 rounded-xl border border-danger p-4 text-sm text-danger">Cancelado: {c.cancelled_reason}</p>}

      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          {editable ? (
            <form action={saveContract.bind(null, id)} className="card space-y-5">
              <h2 className="text-base font-semibold">Dados e cláusulas</h2>
              <Field label="Título"><input name="title" required defaultValue={c.title} className="input" /></Field>
              <div className="grid gap-3 sm:grid-cols-4">
                <Field label="Início"><input name="start_date" type="date" defaultValue={c.start_date ?? ''} className="input" /></Field>
                <Field label="Término"><input name="end_date" type="date" defaultValue={c.end_date ?? ''} className="input" /></Field>
                <Field label="Aviso de renovação (dias)"><input name="renewal_notice_days" type="number" min={0} max={365} defaultValue={c.renewal_notice_days} className="input" /></Field>
                <label className="flex items-center gap-2 pb-2.5 text-sm sm:self-end"><input type="checkbox" name="auto_renew" defaultChecked={c.auto_renew} /> Prevê renovação automática</label>
              </div>
              <div className="grid gap-3 sm:grid-cols-3">
                <Field label="Valor mensal (R$)"><input name="monthly_value" inputMode="decimal" defaultValue={Number(c.monthly_value) ? String(c.monthly_value).replace('.', ',') : ''} className="input" /></Field>
                <Field label="Valor pontual (R$)"><input name="one_time_value" inputMode="decimal" defaultValue={Number(c.one_time_value) ? String(c.one_time_value).replace('.', ',') : ''} className="input" /></Field>
                <Field label="Valor total (R$)"><input name="total_value" inputMode="decimal" defaultValue={Number(c.total_value) ? String(c.total_value).replace('.', ',') : ''} className="input" /></Field>
              </div>
              <Field label="Condições de pagamento"><input name="payment_terms" defaultValue={c.payment_terms} className="input" /></Field>
              <p className="text-xs text-muted">Alterar valores ou datas aqui <b>não reescreve</b> o texto das cláusulas já geradas: ajuste as cláusulas abaixo também.</p>
              <div className="space-y-4">{[...sections, { title: '', body: '' }].map((s, i) => (
                <fieldset key={i} className="rounded-xl border border-line p-3">
                  <legend className="px-1 text-xs text-muted">{i < sections.length ? `Cláusula ${i + 1}` : 'Nova cláusula (opcional)'}</legend>
                  <input name="s_title" defaultValue={s.title} placeholder="Título" className="input mb-2" aria-label={`Título da cláusula ${i + 1}`} />
                  <textarea name="s_body" defaultValue={s.body} rows={Math.min(Math.max(s.body.split('\n').length + 2, 4), 16)} className="input font-mono text-[13px]" aria-label={`Texto da cláusula ${i + 1}`} />
                </fieldset>))}
                <p className="text-xs text-muted">Para remover uma cláusula, apague o título e o texto. Variáveis aceitas: {VARIABLES.map((v) => `{{${v.key}}}`).join(' ')}</p></div>
              <SubmitButton className="btn btn-sm btn-dark" pendingText="Salvando…">Salvar contrato</SubmitButton>
            </form>
          ) : (
            <section className="card space-y-6">
              <div className="grid gap-3 text-sm sm:grid-cols-4">
                <div><div className="label">Vigência</div>{c.start_date ? dateBR(c.start_date) : '—'}{c.end_date ? ` → ${dateBR(c.end_date)}` : ''}</div>
                <div><div className="label">Valor total</div>{Number(c.total_value) ? money(c.total_value) : '—'}</div>
                <div><div className="label">Mensal</div>{Number(c.monthly_value) ? money(c.monthly_value) : '—'}</div>
                <div><div className="label">Renovação</div>{c.auto_renew ? 'prevista' : 'manual'} · aviso {c.renewal_notice_days}d</div>
              </div>
              {sections.map((s, i) => <article key={i}><h3 className="text-sm font-semibold">{i + 1}. {s.title}</h3><p className="mt-1 whitespace-pre-line text-sm text-muted">{s.body}</p></article>)}
              {c.status !== 'rascunho' && c.status !== 'em_revisao' && <p className="text-xs text-muted">Conteúdo travado desde a aprovação. Para alterar, volte para revisão (a aprovação é anulada) ou registre um aditivo.</p>}
            </section>)}
        </div>

        <aside className="space-y-6">
          <section className="card space-y-4">
            <h2 className="text-base font-semibold">Revisão e assinatura</h2>
            {pending > 0 && <p className="rounded-xl border border-warn p-3 text-sm text-warn" role="status">{gaps.blanks} [CAMPO A PREENCHER]{gaps.variables.length ? ` e ${gaps.variables.length} variável(is) sem resolver (${gaps.variables.join(', ')})` : ''}. A aprovação fica bloqueada até preencher tudo.</p>}

            {c.status === 'rascunho' && writer && <form action={sendToReview.bind(null, id)}><SubmitButton className="btn btn-primary w-full" pendingText="…" confirm="Enviar para revisão?">Enviar para revisão</SubmitButton></form>}
            {c.status === 'em_revisao' && <>
              {writer && <form action={backToDraft.bind(null, id)}><SubmitButton className="btn w-full" pendingText="…">Voltar para rascunho</SubmitButton></form>}
              {approver ? (
                <form action={approveContract.bind(null, id)} className="space-y-3 border-t border-line pt-4">
                  <label className="flex items-start gap-2 text-sm"><input type="checkbox" name="confirm" className="mt-0.5" /> Confirmo que este contrato foi revisado por quem de direito (inclusive por profissional jurídico, quando aplicável).</label>
                  <SubmitButton className="btn btn-primary w-full" pendingText="…" confirm="Aprovar e travar o conteúdo para assinatura?">Aprovar e enviar para assinatura</SubmitButton>
                </form>) : <p className="text-sm text-muted">Aguardando aprovação de quem tem a permissão de aprovar contratos.</p>}
            </>}
            {c.status === 'aguardando_assinatura' && <>
              <p className="text-sm">Aprovado por {c.reviewed_by ? 'um responsável' : '—'} em {c.reviewed_at ? dateTimeBR(c.reviewed_at) : '—'}. Conteúdo travado.</p>
              <p className="rounded-xl bg-subtle p-3 text-xs">O orbiahub. <b>ainda não tem integração</b> com serviço de assinatura eletrônica <span className="badge">pendente</span>. Colete a assinatura fora do sistema e registre abaixo como <b>assinatura fora do sistema</b>; isso não é uma assinatura certificada feita pelo orbiahub.</p>
              {writer && <form action={backToReview.bind(null, id)}><SubmitButton className="btn w-full" pendingText="…" confirm="Voltar para revisão? A aprovação será anulada.">Voltar para revisão</SubmitButton></form>}
              {approver && (
                <form action={registerSignature.bind(null, id)} className="space-y-3 border-t border-line pt-4">
                  <Field label="Evidência da assinatura" hint="Como, quando e por quem foi assinado (ex.: PDF assinado por ambas as partes, e-mail de 12/01).">
                    <textarea name="note" required minLength={5} rows={3} className="input" /></Field>
                  <SubmitButton className="btn btn-primary w-full" pendingText="…" confirm="Registrar que o contrato foi assinado fora do sistema?">Registrar assinatura (feita fora do sistema)</SubmitButton>
                </form>)}
            </>}
            {c.status === 'assinado' && <>
              <p className="text-sm">Assinatura registrada em {c.signed_at ? dateTimeBR(c.signed_at) : '—'} <span className="badge">fora do sistema</span></p>
              {c.signature_note && <p className="text-xs text-muted">Evidência: {c.signature_note}</p>}
              {writer && c.end_date && (
                <form action={renewContract.bind(null, id)} className="flex items-end gap-2 border-t border-line pt-4">
                  <Field label="Prorrogar (meses)"><input name="months" type="number" min={1} max={60} defaultValue={12} className="input w-24" /></Field>
                  <SubmitButton className="btn btn-sm" pendingText="…" confirm="Prorrogar a vigência? Confirme as condições com o cliente.">Renovar</SubmitButton>
                </form>)}
              {writer && <form action={closeContract.bind(null, id)}><SubmitButton className="btn btn-sm w-full" pendingText="…" confirm="Encerrar o contrato?">Encerrar contrato</SubmitButton></form>}
            </>}
            {writer && !['encerrado', 'cancelado'].includes(c.status) && (
              <form action={cancelContract.bind(null, id)} className="space-y-2 border-t border-line pt-4">
                <Field label="Cancelar contrato"><input name="reason" required minLength={3} placeholder="Motivo (obrigatório)" className="input" /></Field>
                <SubmitButton className="btn btn-sm btn-danger" pendingText="…" confirm="Cancelar este contrato?">Cancelar</SubmitButton>
              </form>)}
            {writer && c.status === 'rascunho' && <form action={deleteDraft.bind(null, id)}><SubmitButton className="btn btn-sm w-full text-danger" pendingText="…" confirm="Apagar este rascunho?">Apagar rascunho</SubmitButton></form>}
          </section>

          <section className="card"><h2 className="mb-3 text-base font-semibold">Versões</h2>
            <ul className="space-y-1.5 text-sm">{versions?.map((v) => <li key={v.id} className="flex justify-between gap-2"><span>v{v.version}{v.note ? ` · ${v.note}` : ''}</span><span className="text-muted">{dateTimeBR(v.created_at)}</span></li>)}</ul>
            {writer && <form action={saveSnapshot.bind(null, id)} className="mt-4 flex gap-2"><input name="note" placeholder="Nota da versão" className="input" aria-label="Nota da versão" /><SubmitButton className="btn btn-sm" pendingText="…">Salvar versão</SubmitButton></form>}
          </section>

          <section className="card"><h2 className="mb-3 text-base font-semibold">Histórico</h2>
            <ul className="space-y-2 text-sm">{events?.map((e) => <li key={e.id}><div className="font-medium">{EVENT_LABEL[e.kind] ?? e.kind}</div><div className="text-xs text-muted">{e.message ? `${e.message} · ` : ''}{dateTimeBR(e.created_at)}</div></li>)}</ul></section>
        </aside>
      </div>
    </>
  );
}
