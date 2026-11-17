import Link from 'next/link';
import { requireModule } from '@/lib/session';
import { PageHeader, Field, Empty } from '@/components/ui';
import { SubmitButton } from '@/components/SubmitButton';
import { money } from '@/lib/format';
import { CATEGORIES, CATEGORY_LABEL, packageTotals } from '@/lib/catalog';
import { addPackageItem, deletePackage, deleteService, removePackageItem, savePackage, saveService, togglePackage, toggleService } from './actions';

export const metadata = { title: 'Catálogo de Serviços' };

type Service = { id: string; name: string; category: string; description: string | null; deliverables: string[]; billing: 'pontual' | 'mensal'; unit_price: number; active: boolean };

function ServiceForm({ s, manage }: { s?: Service; manage: boolean }) {
  return (
    <form action={saveService.bind(null, s?.id ?? null)} className="grid gap-3 md:grid-cols-[1.4fr_10rem_8rem_9rem]">
      <Field label="Nome"><input name="name" required defaultValue={s?.name} disabled={!manage} className="input" /></Field>
      <Field label="Categoria"><select name="category" defaultValue={s?.category ?? 'outro'} disabled={!manage} className="input">{CATEGORIES.map((c) => <option key={c} value={c}>{CATEGORY_LABEL[c]}</option>)}</select></Field>
      <Field label="Cobrança"><select name="billing" defaultValue={s?.billing ?? 'pontual'} disabled={!manage} className="input"><option value="pontual">Pontual</option><option value="mensal">Mensal (recorrente)</option></select></Field>
      <Field label="Valor (R$)" hint="0 = sob consulta"><input name="unit_price" inputMode="decimal" defaultValue={s && Number(s.unit_price) ? String(s.unit_price).replace('.', ',') : ''} placeholder="0,00" disabled={!manage} className="input" /></Field>
      <div className="md:col-span-2"><Field label="Descrição (vai nos detalhes da proposta)"><textarea name="description" rows={3} defaultValue={s?.description ?? ''} disabled={!manage} className="input" /></Field></div>
      <div className="md:col-span-2"><Field label="Entregáveis padrão (um por linha)"><textarea name="deliverables" rows={3} defaultValue={s?.deliverables.join('\n') ?? ''} disabled={!manage} className="input" /></Field></div>
      {manage && <div className="md:col-span-4"><SubmitButton className="btn btn-sm btn-dark" pendingText="…">{s ? 'Salvar serviço' : 'Criar serviço'}</SubmitButton></div>}
    </form>
  );
}

export default async function Catalogo({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { supabase, can } = await requireModule('catalogo');
  const manage = can('catalog.manage');
  const tab = (await searchParams).tab === 'pacotes' ? 'pacotes' : 'servicos';
  const [{ data: svc }, { data: pkgs }, { data: pitems }] = await Promise.all([
    supabase.from('service_catalog').select('*').order('active', { ascending: false }).order('name'),
    supabase.from('packages').select('*').order('active', { ascending: false }).order('name'),
    supabase.from('package_items').select('id, package_id, service_id, quantity, unit_price_override, position').order('position'),
  ]);
  const services = (svc ?? []) as Service[];
  const byId = new Map(services.map((s) => [s.id, s]));

  return (
    <>
      <PageHeader title="Catálogo de Serviços" subtitle="Serviços, preços e pacotes da sua agência. Ao incluir numa proposta, os dados são copiados: mudar o catálogo não altera propostas já montadas."
        actions={<><Link href="/catalogo" className={`btn ${tab === 'servicos' ? 'btn-dark' : ''}`}>Serviços ({services.length})</Link><Link href="/catalogo?tab=pacotes" className={`btn ${tab === 'pacotes' ? 'btn-dark' : ''}`}>Pacotes ({pkgs?.length ?? 0})</Link></>} />

      {tab === 'servicos' ? (
        <>
          {!services.length && <Empty title="Nenhum serviço no catálogo" text={manage ? 'Cadastre seus serviços com os preços que você pratica. O sistema não preenche valores por você.' : 'Peça a quem gerencia o catálogo para cadastrar os serviços.'} />}
          <div className="space-y-3">{services.map((s) => (
            <details key={s.id} className={`card ${s.active ? '' : 'opacity-60'}`}>
              <summary className="flex cursor-pointer flex-wrap items-center gap-3 text-sm">
                <span className="font-medium">{s.name}</span><span className="badge">{CATEGORY_LABEL[s.category]}</span><span className="badge">{s.billing === 'mensal' ? 'recorrente' : 'pontual'}</span>
                {!s.active && <span className="badge">inativo</span>}
                <span className="ml-auto font-medium">{Number(s.unit_price) ? `${money(s.unit_price)}${s.billing === 'mensal' ? '/mês' : ''}` : 'sob consulta'}</span>
              </summary>
              <div className="mt-5 space-y-4"><ServiceForm s={s} manage={manage} />
                {manage && <div className="flex gap-2 border-t border-line pt-4">
                  <form action={toggleService.bind(null, s.id, !s.active)}><button className="btn btn-sm">{s.active ? 'Desativar' : 'Reativar'}</button></form>
                  <form action={deleteService.bind(null, s.id)}><button className="btn btn-sm btn-danger">Excluir</button></form></div>}
              </div>
            </details>))}</div>
          {manage && <section className="card mt-6"><h2 className="mb-4 text-base font-semibold">Novo serviço</h2><ServiceForm manage /></section>}
        </>
      ) : (
        <>
          {!pkgs?.length && <Empty title="Nenhum pacote" text={manage ? 'Monte pacotes combinando serviços do catálogo (ex.: setup + gestão mensal). Cadastre os serviços primeiro.' : 'Nenhum pacote cadastrado.'} />}
          <div className="space-y-3">{pkgs?.map((k) => {
            const items = (pitems ?? []).filter((i) => i.package_id === k.id);
            const t = packageTotals(items.flatMap((i) => { const s = byId.get(i.service_id); return s ? [{ billing: s.billing, quantity: Number(i.quantity), price: Number(i.unit_price_override ?? s.unit_price) }] : []; }));
            return (
              <details key={k.id} className={`card ${k.active ? '' : 'opacity-60'}`}>
                <summary className="flex cursor-pointer flex-wrap items-center gap-3 text-sm"><span className="font-medium">{k.name}</span>{!k.active && <span className="badge">inativo</span>}
                  <span className="text-xs text-muted">{items.length} serviço(s)</span>
                  <span className="ml-auto text-right font-medium">{t.oneTime ? `${money(t.oneTime)} pontual` : ''}{t.oneTime && t.monthly ? ' + ' : ''}{t.monthly ? `${money(t.monthly)}/mês` : ''}{!t.oneTime && !t.monthly ? 'sem valor' : ''}</span></summary>
                <div className="mt-5 space-y-4">
                  {k.description && <p className="text-sm text-muted">{k.description}</p>}
                  <ul className="divide-y divide-line text-sm">{items.map((i) => { const s = byId.get(i.service_id); return (
                    <li key={i.id} className="flex flex-wrap items-center justify-between gap-2 py-2"><span>{s?.name ?? 'Serviço'} × {Number(i.quantity)}{i.unit_price_override != null && <span className="text-muted"> · preço do pacote</span>}</span>
                      <span className="flex items-center gap-3">{money(Number(i.unit_price_override ?? s?.unit_price ?? 0))}{s?.billing === 'mensal' ? '/mês' : ''}
                        {manage && <form action={removePackageItem.bind(null, i.id)}><button className="btn btn-sm text-danger">Remover</button></form>}</span></li>); })}
                    {!items.length && <li className="py-2 text-muted">Pacote vazio.</li>}</ul>
                  {manage && <>
                    <form action={addPackageItem.bind(null, k.id)} className="grid items-end gap-2 border-t border-line pt-4 sm:grid-cols-[1fr_5rem_9rem_auto]">
                      <Field label="Adicionar serviço"><select name="service" required defaultValue="" className="input"><option value="" disabled>Escolha…</option>{services.filter((s) => s.active && !items.some((i) => i.service_id === s.id)).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}</select></Field>
                      <Field label="Qtd."><input name="quantity" type="number" min="0.01" step="0.01" defaultValue="1" className="input" /></Field>
                      <Field label="Preço no pacote" hint="vazio = catálogo"><input name="price" inputMode="decimal" className="input" /></Field>
                      <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Adicionar</SubmitButton></form>
                    <form action={savePackage.bind(null, k.id)} className="grid items-end gap-2 sm:grid-cols-[1fr_2fr_auto]"><Field label="Nome"><input name="name" defaultValue={k.name} className="input" /></Field><Field label="Descrição"><input name="description" defaultValue={k.description ?? ''} className="input" /></Field><SubmitButton className="btn btn-sm" pendingText="…">Salvar</SubmitButton></form>
                    <div className="flex gap-2"><form action={togglePackage.bind(null, k.id, !k.active)}><button className="btn btn-sm">{k.active ? 'Desativar' : 'Reativar'}</button></form><form action={deletePackage.bind(null, k.id)}><button className="btn btn-sm btn-danger">Excluir</button></form></div></>}
                </div>
              </details>); })}</div>
          {manage && <form action={savePackage.bind(null, null)} className="card mt-6 grid items-end gap-3 sm:grid-cols-[1fr_2fr_auto]"><Field label="Novo pacote"><input name="name" required className="input" /></Field><Field label="Descrição"><input name="description" className="input" /></Field><SubmitButton className="btn btn-sm btn-dark" pendingText="…">Criar pacote</SubmitButton></form>}
        </>
      )}
    </>
  );
}
