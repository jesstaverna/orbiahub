import Link from 'next/link';
import { requireModule } from '@/lib/session';
import { PageHeader, Empty } from '@/components/ui';
import { dateBR, money } from '@/lib/format';
import { todayBR } from '@/lib/domain';
import { STATUS, daysToEnd } from '@/lib/contracts';

export const metadata = { title: 'Contratos' };

export default async function Contratos({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { supabase, can } = await requireModule('contratos');
  const sp = await searchParams;
  const filter = Object.keys(STATUS).includes(sp.status ?? '') ? sp.status! : '';
  let q = supabase.from('contracts').select('id, number, title, status, contract_type, start_date, end_date, monthly_value, total_value, client_id, clients(name)').order('number', { ascending: false }).limit(300);
  if (filter) q = q.eq('status', filter);
  const { data } = await q;
  const today = todayBR();
  const rows = (data ?? []) as unknown as { id: string; number: number; title: string; status: string; contract_type: string; start_date: string | null; end_date: string | null; monthly_value: number; total_value: number; clients: { name: string } | null }[];

  return (
    <>
      <PageHeader title="Contratos" subtitle="Rascunhos gerados das propostas aceitas. Toda revisão e aprovação é humana; o orbiahub. não assina contratos."
        actions={<>{can('contracts.templates') || can('contracts.read') ? <Link href="/contratos/modelos" className="btn">Modelos e cláusulas</Link> : null}{can('contracts.write') && <Link href="/contratos/novo" className="btn btn-primary">Novo contrato</Link>}</>} />
      <nav className="mb-5 flex flex-wrap gap-2 text-sm" aria-label="Filtrar por status">
        <Link href="/contratos" className={`btn btn-sm ${!filter ? 'btn-dark' : ''}`}>Todos</Link>
        {Object.entries(STATUS).map(([k, v]) => <Link key={k} href={`/contratos?status=${k}`} className={`btn btn-sm ${filter === k ? 'btn-dark' : ''}`}>{v.label}</Link>)}
      </nav>
      {!rows.length ? <Empty title="Nenhum contrato" text={can('contracts.write') ? 'Gere o primeiro a partir de uma proposta aceita (Propostas → Gerar contrato) ou de um modelo.' : 'Nenhum contrato cadastrado.'} action={can('contracts.write') ? <Link href="/contratos/novo" className="btn btn-primary">Novo contrato</Link> : undefined} /> : (
        <div className="overflow-x-auto rounded-2xl border border-line bg-surface">
          <table className="w-full min-w-[720px] text-left">
            <thead><tr className="border-b border-line"><th className="th">Nº</th><th className="th">Contrato</th><th className="th">Status</th><th className="th">Vigência</th><th className="th text-right">Valor</th></tr></thead>
            <tbody>{rows.map((r) => {
              const d = r.status === 'assinado' ? daysToEnd(r.end_date, today) : null;
              return (
                <tr key={r.id} className="border-b border-line last:border-0 hover:bg-subtle">
                  <td className="td text-muted">#{r.number}</td>
                  <td className="td"><Link href={`/contratos/${r.id}`} className="font-medium underline-offset-2 hover:underline">{r.title}</Link><div className="text-xs text-muted">{r.clients?.name ?? '—'}</div></td>
                  <td className="td"><span className={`badge ${STATUS[r.status]?.tone ?? ''}`}>{STATUS[r.status]?.label ?? r.status}</span></td>
                  <td className="td text-sm">{r.start_date ? dateBR(r.start_date) : '—'}{r.end_date ? ` → ${dateBR(r.end_date)}` : ''}
                    {d != null && d <= 30 && <div className={`text-xs ${d < 0 ? 'text-danger' : 'text-warn'}`}>{d < 0 ? `vigência encerrada há ${-d} dia(s)` : `vence em ${d} dia(s)`}</div>}</td>
                  <td className="td text-right text-sm">{Number(r.total_value) ? money(r.total_value) : '—'}{Number(r.monthly_value) ? <div className="text-xs text-muted">{money(r.monthly_value)}/mês</div> : null}</td>
                </tr>); })}</tbody>
          </table>
        </div>)}
    </>
  );
}
