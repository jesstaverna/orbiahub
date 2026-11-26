import { requireModule } from '@/lib/session';
import { PageHeader, Field, Empty } from '@/components/ui';
import { SubmitButton } from '@/components/SubmitButton';
import { LEGAL_NOTICE, SERVICE_TYPE_LABEL } from '@/lib/contracts';
import { generateContract } from '../actions';

export const metadata = { title: 'Novo contrato' };

export default async function NovoContrato({ searchParams }: { searchParams: Promise<{ proposal?: string }> }) {
  const { supabase, can } = await requireModule('contratos');
  if (!can('contracts.write')) return <p className="text-sm text-muted">Seu perfil pode consultar contratos, mas não gerá-los.</p>;
  const sp = await searchParams;
  const pre = sp.proposal && /^[0-9a-f-]{36}$/.test(sp.proposal) ? sp.proposal : '';
  const [{ data: templates }, { data: proposals }, { data: used }, { data: clients }] = await Promise.all([
    supabase.from('contract_templates').select('id, name, service_type').eq('active', true).order('name'),
    supabase.from('proposals').select('id, number, title, client_display_name, client_id').eq('status', 'aceita').not('client_id', 'is', null).order('number', { ascending: false }).limit(200),
    supabase.from('contracts').select('proposal_id').not('proposal_id', 'is', null).neq('status', 'cancelado'),
    supabase.from('clients').select('id, name').order('name').limit(500),
  ]);
  const taken = new Set((used ?? []).map((u) => u.proposal_id));
  const free = (proposals ?? []).filter((p) => !taken.has(p.id));

  return (
    <>
      <PageHeader title="Novo contrato" subtitle="Gera um RASCUNHO a partir de um modelo. Nada é enviado nem assinado." />
      <p className="mb-6 max-w-3xl rounded-xl border border-line bg-subtle p-4 text-sm">{LEGAL_NOTICE}</p>
      {!templates?.length ? <Empty title="Nenhum modelo ativo" text="Peça a quem gerencia os modelos para criar ou ativar um modelo de contrato." /> : (
        <form action={generateContract} className="card grid max-w-3xl gap-4 sm:grid-cols-2">
          <div className="sm:col-span-2"><Field label="Modelo" hint="Escolha o modelo do tipo de serviço. Você poderá editar todas as cláusulas.">
            <select name="template" required defaultValue="" className="input"><option value="" disabled>Escolha…</option>{templates.map((t) => <option key={t.id} value={t.id}>{t.name} — {SERVICE_TYPE_LABEL[t.service_type]}</option>)}</select></Field></div>
          <Field label="Proposta aceita" hint="Preenche cliente, serviços, valores e prazos automaticamente.">
            <select name="proposal" defaultValue={pre} className="input"><option value="">— sem proposta —</option>{free.map((p) => <option key={p.id} value={p.id}>#{p.number} · {p.client_display_name} · {p.title}</option>)}</select></Field>
          <Field label="…ou cliente (sem proposta)" hint="Usado só se nenhuma proposta for escolhida.">
            <select name="client" defaultValue="" className="input"><option value="">—</option>{clients?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
          <Field label="Início da vigência"><input name="start" type="date" className="input" /></Field>
          <Field label="Título (opcional)"><input name="title" className="input" placeholder="Contrato de prestação de serviços — cliente" /></Field>
          <div className="sm:col-span-2"><SubmitButton className="btn btn-primary" pendingText="Gerando…">Gerar rascunho</SubmitButton></div>
        </form>)}
    </>
  );
}
