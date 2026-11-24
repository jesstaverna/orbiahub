import { Palette, Plus, Building2 } from 'lucide-react';
import { requireModule } from '@/lib/session';
import { PageHeader, Empty } from '@/components/ui';
import { saveBrand, setBrandActive } from './actions';

export const metadata = { title: 'Brand Center' };

type Brand = { id: string; name: string; segment: string; tone_of_voice: string; primary_color: string; secondary_color: string; client_id: string | null; active: boolean };
type Client = { id: string; name: string };

function BrandForm({ brand, clients }: { brand?: Brand; clients: Client[] }) {
  return <form action={saveBrand} className="grid gap-4 sm:grid-cols-2">
    {brand && <input type="hidden" name="id" value={brand.id} />}
    <label className="block"><span className="mb-1 block text-sm font-medium">Nome da marca</span><input className="input w-full" name="name" required maxLength={100} defaultValue={brand?.name} /></label>
    <label className="block"><span className="mb-1 block text-sm font-medium">Segmento</span><input className="input w-full" name="segment" maxLength={120} defaultValue={brand?.segment} /></label>
    <label className="block sm:col-span-2"><span className="mb-1 block text-sm font-medium">Cliente vinculado</span><select className="input w-full" name="client_id" defaultValue={brand?.client_id ?? ''}><option value="">Marca interna / sem cliente</option>{brand?.client_id && !clients.some(c => c.id === brand.client_id) && <option value={brand.client_id}>Cliente vinculado</option>}{clients.map(c => <option value={c.id} key={c.id}>{c.name}</option>)}</select></label>
    <label className="block"><span className="mb-1 block text-sm font-medium">Cor principal</span><input className="input h-10 w-full" type="color" name="primary_color" defaultValue={brand?.primary_color ?? '#7C5CFF'} /></label>
    <label className="block"><span className="mb-1 block text-sm font-medium">Cor secundária</span><input className="input h-10 w-full" type="color" name="secondary_color" defaultValue={brand?.secondary_color ?? '#EC4899'} /></label>
    <label className="block sm:col-span-2"><span className="mb-1 block text-sm font-medium">Tom de voz e diretrizes</span><textarea className="input w-full" name="tone_of_voice" maxLength={4000} rows={4} defaultValue={brand?.tone_of_voice} /></label>
    <div className="sm:col-span-2"><button className="btn btn-primary" type="submit">{brand ? 'Salvar alterações' : 'Criar marca'}</button></div>
  </form>;
}

export default async function BrandPage() {
  const { supabase, can } = await requireModule('brand');
  const edit = can('settings.manage');
  const { data, error } = await supabase.from('marketing_brands').select('id,name,segment,tone_of_voice,primary_color,secondary_color,client_id,active').order('name');
  const clientsResult = edit ? await supabase.from('clients').select('id,name').order('name') : { data: [], error: null };
  const brands: Brand[] = data ?? [];
  const clients: Client[] = clientsResult.data ?? [];
  return <div className="space-y-6">
    <PageHeader title="Brand Center" subtitle="Centralize suas marcas, identidade visual e diretrizes de comunicação." />
    {error ? <div role="alert" className="card">O banco de marcas ainda não está disponível ou não pôde ser consultado. Nenhum dado foi simulado.</div> : <>
      <div className="grid gap-4 sm:grid-cols-3">
        {[[brands.length,'Marcas cadastradas'],[brands.filter(b => b.active).length,'Marcas ativas'],[brands.filter(b => b.client_id).length,'Vinculadas a clientes']].map(([n,label]) => <div key={label} className="card"><p className="text-sm opacity-75">{label}</p><p className="mt-2 text-3xl font-semibold">{n}</p></div>)}
      </div>
      {edit && <details className="card"><summary className="cursor-pointer font-semibold"><Plus className="mr-2 inline h-4 w-4" />Nova marca</summary><div className="mt-5">{clientsResult.error && <p role="alert" className="mb-3 text-sm">Não foi possível carregar os clientes. Você pode cadastrar uma marca interna.</p>}<BrandForm clients={clients}/></div></details>}
      {!brands.length ? <Empty title="Nenhuma marca cadastrada" description="Cadastre sua primeira marca para organizar a operação de marketing." /> : <div className="grid gap-4 xl:grid-cols-2">
        {brands.map(b => <article key={b.id} className="card space-y-4">
          <div className="flex items-start gap-3"><div className="rounded-xl border p-3"><Palette className="h-5 w-5"/></div><div className="min-w-0 flex-1"><h2 className="break-words font-semibold">{b.name}</h2><p className="text-sm opacity-75">{b.segment || 'Sem segmento definido'}</p></div><span className="badge">{b.active ? 'Ativa' : 'Arquivada'}</span></div>
          <div className="flex flex-wrap gap-3">{[b.primary_color,b.secondary_color].map((color,i) => <div key={i} className="flex items-center gap-2 text-xs"><span className="h-6 w-6 rounded-md border" style={{ backgroundColor: color }}/>{color}</div>)}</div>
          <p className="flex items-center gap-2 text-sm"><Building2 className="h-4 w-4"/>{b.client_id ? clients.find(c => c.id === b.client_id)?.name ?? 'Cliente vinculado' : 'Marca interna / independente'}</p>
          <p className="whitespace-pre-wrap break-words text-sm opacity-80">{b.tone_of_voice || 'Nenhuma diretriz de comunicação registrada.'}</p>
          {edit && <><details className="border-t pt-3"><summary className="cursor-pointer text-sm font-medium">Editar marca</summary><div className="mt-4"><BrandForm brand={b} clients={clients}/></div></details><form action={setBrandActive}><input type="hidden" name="id" value={b.id}/><input type="hidden" name="active" value={String(!b.active)}/><button className="btn" type="submit">{b.active ? 'Arquivar' : 'Reativar'}</button></form></>}
        </article>)}
      </div>}
    </>}
  </div>;
}
