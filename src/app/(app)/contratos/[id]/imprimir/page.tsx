import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireModule } from '@/lib/session';
import { PrintButton } from '@/components/ClientButtons';
import { dateBR } from '@/lib/format';
import { EDITABLE, STATUS, findPlaceholders, type Section } from '@/lib/contracts';

export const metadata = { title: 'Contrato — impressão', robots: { index: false } };

/** Versão limpa para imprimir ou "Salvar como PDF". Enquanto não aprovado, leva marca d'água de RASCUNHO. */
export default async function Imprimir({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/.test(id)) notFound();
  const { supabase, agency } = await requireModule('contratos');
  const { data: c } = await supabase.from('contracts').select('number, title, status, content, start_date, end_date, clients(name)').eq('id', id).maybeSingle();
  if (!c) notFound();
  const sections = (c.content ?? []) as Section[];
  const draft = EDITABLE.includes(c.status);
  const gaps = findPlaceholders(sections);
  return (
    <div className="-mx-4 -mt-20 sm:-mx-6 lg:-mx-10 lg:-mt-6">
      <div className="no-print sticky top-0 z-10 flex items-center justify-between gap-2 border-b border-line bg-bg px-6 py-3 text-sm">
        <Link href={`/contratos/${id}`} className="btn btn-sm">← Voltar</Link>
        <span className="text-muted">{STATUS[c.status]?.label}{gaps.blanks ? ` · ${gaps.blanks} lacuna(s) a preencher` : ''}</span>
        <PrintButton />
      </div>
      <article className="relative mx-auto max-w-3xl bg-white px-8 py-12 text-black">
        {draft && <div aria-hidden className="pointer-events-none absolute inset-0 grid place-items-center text-7xl font-bold uppercase tracking-widest text-black/5 print:text-black/10" style={{ transform: 'rotate(-20deg)' }}>Rascunho</div>}
        <header className="mb-10 border-b border-black/20 pb-6">
          <p className="text-xs uppercase tracking-widest text-black/50">{agency.name} · Contrato nº {c.number}</p>
          <h1 className="mt-2 text-2xl font-semibold">{c.title}</h1>
          <p className="mt-1 text-sm text-black/60">{(c.clients as unknown as { name: string } | null)?.name}{c.start_date ? ` · ${dateBR(c.start_date)}` : ''}{c.end_date ? ` a ${dateBR(c.end_date)}` : ''}</p>
        </header>
        <div className="space-y-6">{sections.map((s, i) => <section key={i}><h2 className="text-sm font-semibold uppercase tracking-wide">{i + 1}. {s.title}</h2><p className="mt-1.5 whitespace-pre-line text-[13.5px] leading-relaxed">{s.body}</p></section>)}</div>
        <footer className="mt-16 grid grid-cols-2 gap-10 text-xs"><div className="border-t border-black pt-2">CONTRATANTE</div><div className="border-t border-black pt-2">CONTRATADA</div></footer>
        {draft && <p className="mt-8 text-[11px] text-black/50">Documento em elaboração — sujeito a revisão jurídica. Não assinar enquanto houver campos a preencher.</p>}
      </article>
    </div>
  );
}
