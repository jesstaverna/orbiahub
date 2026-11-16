import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { Suspense } from 'react';
import { createClient } from '@/lib/supabase/server';
import { requirePlatform, flash } from '@/lib/session';
import { createAdminClient } from '@/lib/supabase/admin';
import { Flash } from '@/components/Flash';
import { SubmitButton } from '@/components/SubmitButton';
import { Field, PageHeader, Empty } from '@/components/ui';
import { dateTimeBR } from '@/lib/format';
import { Logo } from '@/components/Logo';

export const metadata = { title: 'Plataforma' };

async function signOut() { 'use server'; const s = await createClient(); await s.auth.signOut(); redirect('/login'); }

const slugify = (v: string) => v.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

/** Cria a agência e vincula o proprietário. O administrador da plataforma NÃO ganha acesso aos dados de negócio da agência. */
async function createAgency(fd: FormData) {
  'use server';
  const { supabase } = await requirePlatform();
  const name = String(fd.get('name') ?? '').trim();
  const slug = slugify(String(fd.get('slug') ?? '') || name);
  const email = String(fd.get('owner_email') ?? '').trim().toLowerCase();
  const plan = String(fd.get('plan') ?? 'trial');
  if (!name || !slug) flash('/plataforma', 'err', 'Informe o nome da agência.');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) flash('/plataforma', 'err', 'Informe o e-mail do proprietário.');
  if (process.env.SUPABASE_SERVICE_ROLE_KEY) {
    try { await createAdminClient().auth.admin.inviteUserByEmail(email); } catch { /* já cadastrado */ }
  }
  const { error } = await supabase.rpc('platform_create_agency', { p_name: name, p_slug: slug, p_owner_email: email, p_plan: plan });
  if (error) flash('/plataforma', 'err', error.code === '23505' ? 'Já existe uma agência com esse endereço (slug).' : error.code === '23514' ? 'O proprietário precisa ter conta e não pertencer a outra agência.' : 'Não foi possível criar a agência.');
  revalidatePath('/plataforma');
  flash('/plataforma', 'ok', 'Agência criada e proprietário vinculado.');
}

async function setAgency(id: string, fd: FormData) {
  'use server';
  const { supabase } = await requirePlatform();
  const { error } = await supabase.rpc('platform_set_agency', { p_id: id, p_plan: String(fd.get('plan') ?? ''), p_status: String(fd.get('status') ?? '') });
  if (error) flash('/plataforma', 'err', 'Não foi possível atualizar a agência.');
  revalidatePath('/plataforma');
  flash('/plataforma', 'ok', 'Agência atualizada.');
}

export default async function Plataforma() {
  const { supabase, profile } = await requirePlatform();
  const [{ data: agencies }, { data: plans }] = await Promise.all([
    supabase.from('agencies').select('id, name, slug, plan, status, created_at').order('created_at'),
    supabase.from('plans').select('key, name, active').order('key'),
  ]);
  return (
    <main className="mx-auto max-w-5xl px-4 py-10 sm:px-6">
      <Suspense><Flash /></Suspense>
      <div className="mb-8"><Logo className="h-8" /></div>
      <PageHeader title="Plataforma" subtitle="Agências e planos. Esta área não exibe dados de negócio das agências (clientes, propostas, financeiro)."
        actions={<form action={signOut}><button className="btn btn-sm">Sair ({profile.email})</button></form>} />

      <section className="card mb-8"><h2 className="mb-4 text-base font-semibold">Nova agência</h2>
        <form action={createAgency} className="grid items-end gap-3 md:grid-cols-[1.2fr_1fr_1.2fr_9rem_auto]">
          <Field label="Nome"><input name="name" required className="input" /></Field>
          <Field label="Endereço (slug)" hint="Opcional; gerado do nome."><input name="slug" className="input" pattern="[a-z0-9]+(-[a-z0-9]+)*" /></Field>
          <Field label="E-mail do proprietário"><input name="owner_email" type="email" required className="input" /></Field>
          <Field label="Plano"><select name="plan" defaultValue="trial" className="input">{plans?.filter((p) => p.active).map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}</select></Field>
          <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Criar</SubmitButton>
        </form>
        <p className="mt-3 text-xs text-muted">O proprietário recebe um convite por e-mail (requer a chave de serviço no servidor) e vira administrador da agência. Os limites de cada plano são configuráveis na tabela <code>plans</code>.</p>
      </section>

      <section className="card"><h2 className="mb-4 text-base font-semibold">Agências ({agencies?.length ?? 0})</h2>
        {!agencies?.length ? <Empty title="Nenhuma agência ainda" text="Crie a primeira agência acima." /> : (
          <div className="space-y-3">{agencies.map((a) => (
            <form key={a.id} action={setAgency.bind(null, a.id)} className={`grid items-end gap-3 rounded-xl border border-line p-3 md:grid-cols-[1.4fr_9rem_9rem_auto] ${a.status === 'suspended' ? 'opacity-70' : ''}`}>
              <div><div className="font-medium">{a.name}</div><div className="text-xs text-muted">{a.slug} · criada em {dateTimeBR(a.created_at)}</div></div>
              <Field label="Plano"><select name="plan" defaultValue={a.plan} className="input">{plans?.map((p) => <option key={p.key} value={p.key}>{p.name}</option>)}</select></Field>
              <Field label="Status"><select name="status" defaultValue={a.status} className="input"><option value="active">Ativa</option><option value="suspended">Suspensa</option></select></Field>
              <SubmitButton className="btn btn-sm" pendingText="…">Salvar</SubmitButton>
            </form>))}</div>)}
        <p className="mt-4 text-xs text-muted">Suspender uma agência bloqueia imediatamente o acesso de todos os usuários dela; os dados são preservados.</p>
      </section>
    </main>
  );
}
