import { revalidatePath } from 'next/cache';
import { requireModule, flash } from '@/lib/session';
import { PageHeader, Field, Pending } from '@/components/ui';
import { SubmitButton } from '@/components/SubmitButton';
import { LOCKED_ROLES, PERMISSIONS, PERMISSION_KEYS } from '@/lib/permissions';
import { dateTimeBR } from '@/lib/format';
import { createAdminClient } from '@/lib/supabase/admin';
import { isHexColor } from '@/lib/brand';

export const metadata = { title: 'Configurações' };

async function updateUser(id: string, fd: FormData) {
  'use server';
  const { supabase, profile } = await requireModule('configuracoes');
  const role = String(fd.get('role'));
  const active = fd.get('active') === 'on';
  if (id === profile.id && (role !== 'admin' || !active)) flash('/configuracoes', 'err', 'Você não pode remover seu próprio acesso de administrador.');
  const patch: Record<string, unknown> = { role, active, full_name: String(fd.get('full_name') ?? '').trim() };
  patch.client_id = role === 'cliente' ? String(fd.get('client_id') ?? '') || null : null;
  const { error } = await supabase.from('profiles').update(patch).eq('id', id);
  if (error) flash('/configuracoes', 'err', error.code === '23503' ? 'Perfil inexistente nesta agência.' : 'Não foi possível atualizar o usuário.');
  revalidatePath('/configuracoes');
  flash('/configuracoes', 'ok', 'Usuário atualizado.');
}

/** Convida por e-mail (se houver chave de serviço) e vincula à agência. Quem já pertence a outra agência NUNCA é movido. */
async function addMember(fd: FormData) {
  'use server';
  const { supabase } = await requireModule('configuracoes');
  const email = String(fd.get('email') ?? '').trim().toLowerCase();
  const role = String(fd.get('role') ?? '');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) flash('/configuracoes', 'err', 'Informe um e-mail válido.');
  if (process.env.SUPABASE_SERVICE_ROLE_KEY) {
    try { await createAdminClient().auth.admin.inviteUserByEmail(email); } catch { /* já cadastrado ou convite indisponível: segue para o vínculo */ }
  }
  const { data, error } = await supabase.rpc('agency_add_member', { p_email: email, p_role: role });
  if (error) flash('/configuracoes', 'err', error.code === '53400' ? 'Limite de usuários do plano atingido. Faça upgrade para adicionar mais.' : error.code === '22023' ? 'Perfil inválido.' : 'Não foi possível adicionar o usuário.');
  if (!data) flash('/configuracoes', 'err', 'Usuário não encontrado ou já vinculado a outra agência. Peça para ele criar a conta com este e-mail e tente de novo.');
  revalidatePath('/configuracoes');
  flash('/configuracoes', 'ok', 'Usuário adicionado à agência.');
}

const roleKey = (name: string) => {
  const k = name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 28);
  return /^[a-z]/.test(k) ? k : `p_${k}`;
};

async function createRole(fd: FormData) {
  'use server';
  const { supabase } = await requireModule('configuracoes');
  const name = String(fd.get('name') ?? '').trim();
  const key = roleKey(name);
  if (!name || key.length < 3) flash('/configuracoes#papeis', 'err', 'Informe um nome para o perfil (mínimo 3 letras).');
  const { error } = await supabase.from('roles').insert({ key, name, permissions: ['app.access', 'clients.read'] });
  if (error) flash('/configuracoes#papeis', 'err', error.code === '23505' ? 'Já existe um perfil com esse nome.' : 'Não foi possível criar o perfil.');
  revalidatePath('/configuracoes');
  flash('/configuracoes#papeis', 'ok', 'Perfil criado com permissões mínimas. Marque o que ele pode fazer e salve.');
}

async function saveRole(key: string, fd: FormData) {
  'use server';
  const { supabase } = await requireModule('configuracoes');
  if (LOCKED_ROLES.includes(key)) flash('/configuracoes#papeis', 'err', 'Administrador e Cliente são perfis fixos.');
  const permissions = fd.getAll('perm').map(String).filter((p) => PERMISSION_KEYS.includes(p));
  const name = String(fd.get('name') ?? '').trim();
  if (!name) flash('/configuracoes#papeis', 'err', 'O perfil precisa de um nome.');
  const { data, error } = await supabase.from('roles').update({ name, permissions }).eq('key', key).select('key');
  if (error || !data?.length) flash('/configuracoes#papeis', 'err', 'Não foi possível salvar o perfil.');
  revalidatePath('/', 'layout');
  flash('/configuracoes#papeis', 'ok', 'Perfil salvo. Vale imediatamente para quem o usa.');
}

async function deleteRole(key: string) {
  'use server';
  const { supabase } = await requireModule('configuracoes');
  const { error } = await supabase.from('roles').delete().eq('key', key);
  if (error) flash('/configuracoes#papeis', 'err', error.code === '23503' ? 'Há usuários com este perfil. Mude o perfil deles antes de remover.' : 'Perfis de sistema não podem ser removidos.');
  revalidatePath('/configuracoes');
  flash('/configuracoes#papeis', 'ok', 'Perfil removido.');
}

async function saveAgency(fd: FormData) {
  'use server';
  const { supabase, agency } = await requireModule('configuracoes');
  const name = String(fd.get('name') ?? '').trim();
  const primary = String(fd.get('primary') ?? '').trim();
  if (!name) flash('/configuracoes#agencia', 'err', 'Informe o nome da agência.');
  if (primary && !isHexColor(primary)) flash('/configuracoes#agencia', 'err', 'Use uma cor no formato #RRGGBB.');
  const brand = { ...(agency.brand ?? {}), ...(primary ? { primary } : { primary: undefined }) };
  const { data, error } = await supabase.from('agencies').update({ name, brand }).eq('id', agency.id).select('id');
  if (error || !data?.length) flash('/configuracoes#agencia', 'err', 'Não foi possível salvar a identidade da agência.');
  revalidatePath('/', 'layout');
  flash('/configuracoes#agencia', 'ok', 'Identidade da agência salva.');
}

async function saveStage(id: string | null, fd: FormData) {
  'use server';
  const { supabase } = await requireModule('configuracoes');
  const name = String(fd.get('name') ?? '').trim();
  if (!name) flash('/configuracoes#funil', 'err', 'Informe o nome da etapa.');
  const row = { name, probability: Math.min(Math.max(Number(fd.get('probability') ?? 0) || 0, 0), 100), position: Number(fd.get('position') ?? 0) || 0, active: fd.get('active') === 'on' };
  const kind = String(fd.get('kind') ?? 'open');
  const q = id ? supabase.from('pipeline_stages').update(row).eq('id', id) : supabase.from('pipeline_stages').insert({ ...row, kind: ['open', 'won', 'lost'].includes(kind) ? kind : 'open', is_negotiation: false });
  const { error } = await q;
  if (error) flash('/configuracoes#funil', 'err', error.code === '23505' ? 'Já existe uma etapa ativa nessa posição — use um número livre.' : 'Não foi possível salvar a etapa.');
  revalidatePath('/crm');
  flash('/configuracoes#funil', 'ok', 'Etapa salva.');
}

const INTEGRATIONS = [
  { name: 'RD Station Marketing', phase: 'Fase 3', need: 'Conta + credenciais OAuth (client id/secret) no plano contratado' },
  { name: 'RD Conversas (agente de IA no WhatsApp)', phase: 'Fase 3', need: 'Assinatura do RD Conversas — ainda não contratada. Nada simulado.' },
  { name: 'Clicksign / ZapSign (assinatura)', phase: 'Fase 3', need: 'Conta e token de API' },
  { name: 'Meta Ads', phase: 'Fase 3', need: 'App Meta + token com acesso às contas de anúncio dos clientes' },
  { name: 'Google Ads', phase: 'Fase 3', need: 'Developer token + OAuth' },
  { name: 'Asaas (cobrança)', phase: 'Fase 3', need: 'Chave de API (sandbox para homologação)' },
  { name: 'Claude API (agentes de IA)', phase: 'Fase 4', need: 'ANTHROPIC_API_KEY no servidor' },
];

export default async function Config() {
  const { supabase, profile, agency } = await requireModule('configuracoes');
  const [{ data: users }, { data: stages }, { data: clients }, { data: audit }, { data: plan }, { data: roles }] = await Promise.all([
    supabase.from('profiles').select('id, full_name, email, role, active, client_id, created_at').order('created_at'),
    supabase.from('pipeline_stages').select('*').order('position'),
    supabase.from('clients').select('id, name, status').order('name'),
    supabase.from('audit_log').select('id, table_name, action, created_at, actor_id').order('created_at', { ascending: false }).limit(15),
    supabase.from('plans').select('name, max_users, max_clients').eq('key', agency.plan).maybeSingle(),
    supabase.from('roles').select('key, name, permissions, is_system').order('is_system', { ascending: false }).order('name'),
  ]);
  const roleList = (roles ?? []) as { key: string; name: string; permissions: string[]; is_system: boolean }[];
  const groups = [...new Set(PERMISSIONS.map((p) => p.group))];
  const activeUsers = users?.filter((u) => u.active).length ?? 0;
  const limit = (n: number, max: number | null | undefined) => (max == null ? `${n} (ilimitado)` : `${n} de ${max}`);
  const names = new Map(users?.map((u) => [u.id, u.full_name || u.email]));
  return (
    <>
      <PageHeader title="Configurações" subtitle="Usuários e permissões, funil comercial, integrações e auditoria." />

      <section id="agencia" className="card mb-8"><h2 className="mb-1 text-base font-semibold">Agência e plano</h2>
        <p className="mb-5 text-sm text-muted">Nome e cor de destaque aparecem no menu, nos documentos e nas propostas enviadas aos seus clientes. Plano e status são gerenciados pela plataforma.</p>
        <form action={saveAgency} className="grid items-end gap-3 sm:grid-cols-[1fr_12rem_auto]">
          <Field label="Nome da agência"><input name="name" required defaultValue={agency.name} className="input" /></Field>
          <Field label="Cor de destaque" hint="Formato #RRGGBB. Vazio = padrão orbiahub."><input name="primary" defaultValue={agency.brand?.primary ?? ''} placeholder="#7C5CFF" pattern="#[0-9a-fA-F]{6}" className="input" /></Field>
          <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Salvar</SubmitButton>
        </form>
        <dl className="mt-5 grid gap-3 border-t border-line pt-4 text-sm sm:grid-cols-3">
          <div><dt className="label">Plano</dt><dd>{plan?.name ?? agency.plan}</dd></div>
          <div><dt className="label">Usuários ativos</dt><dd>{limit(activeUsers, plan?.max_users)}</dd></div>
          <div><dt className="label">Clientes cadastrados</dt><dd>{limit(clients?.filter((c) => c.status !== 'encerrado').length ?? 0, plan?.max_clients)}</dd></div>
        </dl></section>

      <section className="card mb-8"><h2 className="mb-1 text-base font-semibold">Usuários e perfis</h2>
        <p className="mb-5 text-sm text-muted">Adicione pessoas à sua agência pelo e-mail e defina o perfil. Cada usuário pertence a <b>uma</b> agência e só enxerga os dados dela. Contas “Cliente” só terão portal na Fase 2.</p>
        <form action={addMember} className="mb-5 grid items-end gap-3 rounded-xl border border-dashed border-line p-3 sm:grid-cols-[1fr_11rem_auto]">
          <Field label="Adicionar usuário (e-mail)"><input name="email" type="email" required autoComplete="off" className="input" /></Field>
          <Field label="Perfil"><select name="role" defaultValue="comercial" className="input">{roleList.filter((r) => r.key !== 'cliente').map((r) => <option key={r.key} value={r.key}>{r.name}</option>)}</select></Field>
          <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Adicionar</SubmitButton>
        </form>
        <div className="space-y-3">{users?.map((u) => (
          <form key={u.id} action={updateUser.bind(null, u.id)} className="grid items-end gap-3 rounded-xl border border-line p-3 md:grid-cols-[1.2fr_1.2fr_11rem_1fr_auto_auto]">
            <div><span className="label">E-mail</span><div className="truncate text-sm">{u.email}</div></div>
            <Field label="Nome"><input name="full_name" defaultValue={u.full_name} className="input" /></Field>
            <Field label="Perfil"><select name="role" defaultValue={u.role} className="input">{roleList.map((r) => <option key={r.key} value={r.key}>{r.name}</option>)}</select></Field>
            <Field label="Cliente (portal)"><select name="client_id" defaultValue={u.client_id ?? ''} className="input"><option value="">—</option>{clients?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
            <label className="flex items-center gap-2 pb-2.5 text-sm"><input type="checkbox" name="active" defaultChecked={u.active} /> Ativo</label>
            <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Salvar</SubmitButton>
          </form>))}</div></section>

      <section id="papeis" className="card mb-8"><h2 className="mb-1 text-base font-semibold">Perfis e permissões</h2>
        <p className="mb-5 text-sm text-muted">Cada perfil é um conjunto de permissões, aplicado também no banco de dados (não só no menu). Os perfis de sistema vêm com padrões editáveis, inclusive <b>Gestor / Head</b>; crie perfis próprios abaixo. <b>Administrador</b> e <b>Cliente</b> são fixos para ninguém trancar a agência.</p>
        <div className="space-y-3">{roleList.map((r) => {
          const locked = LOCKED_ROLES.includes(r.key);
          const inUse = users?.filter((u) => u.role === r.key).length ?? 0;
          return (
            <details key={r.key} className="rounded-xl border border-line p-3">
              <summary className="flex cursor-pointer flex-wrap items-center gap-2 text-sm font-medium">{r.name}
                <span className="badge">{r.is_system ? 'sistema' : 'personalizado'}</span>{locked && <span className="badge">fixo</span>}
                <span className="text-xs font-normal text-muted">{inUse} usuário(s) · {r.permissions.length} permissões</span></summary>
              <form action={saveRole.bind(null, r.key)} className="mt-4 space-y-4">
                <Field label="Nome do perfil"><input name="name" defaultValue={r.name} disabled={locked} className="input max-w-sm" /></Field>
                <div className="grid gap-4 md:grid-cols-2">{groups.map((g) => (
                  <fieldset key={g}><legend className="label">{g}</legend>
                    {PERMISSIONS.filter((p) => p.group === g).map((p) => (
                      <label key={p.key} className="flex items-start gap-2 py-1 text-sm"><input type="checkbox" name="perm" value={p.key} defaultChecked={r.permissions.includes(p.key)} disabled={locked} className="mt-0.5" />{p.label}</label>))}
                  </fieldset>))}</div>
                {!locked && <div className="flex gap-2"><SubmitButton className="btn btn-sm btn-dark" pendingText="…">Salvar perfil</SubmitButton></div>}
              </form>
              {!r.is_system && <form action={deleteRole.bind(null, r.key)} className="mt-3"><SubmitButton className="btn btn-sm btn-danger" pendingText="…">Remover perfil</SubmitButton></form>}
            </details>);})}</div>
        <form action={createRole} className="mt-5 grid items-end gap-3 border-t border-line pt-5 sm:grid-cols-[1fr_auto]">
          <Field label="Novo perfil" hint="Nasce só com “entrar no sistema” e “ver clientes”; você marca o resto."><input name="name" required minLength={3} className="input" /></Field>
          <SubmitButton className="btn btn-sm btn-dark" pendingText="…">Criar perfil</SubmitButton>
        </form></section>

      <section id="funil" className="card mb-8"><h2 className="mb-1 text-base font-semibold">Etapas do funil</h2>
        <p className="mb-5 text-sm text-muted">Renomeie, reordene (posição única entre etapas ativas) e ajuste a probabilidade usada nas previsões. As probabilidades iniciais são estimativas suas para calibrar — não são dados históricos.</p>
        <div className="space-y-2">{stages?.map((s) => (
          <form key={s.id} action={saveStage.bind(null, s.id)} className={`grid items-end gap-3 sm:grid-cols-[1fr_6rem_6rem_auto_auto] ${s.active ? '' : 'opacity-60'}`}>
            <Field label={`${s.kind === 'won' ? 'Ganho' : s.kind === 'lost' ? 'Perdido' : 'Aberta'}${s.is_negotiation ? ' · negociação' : ''}`}><input name="name" defaultValue={s.name} className="input" /></Field>
            <Field label="Posição"><input name="position" type="number" defaultValue={s.position} className="input" /></Field><Field label="Prob. %"><input name="probability" type="number" min={0} max={100} defaultValue={s.probability} className="input" /></Field>
            <label className="flex items-center gap-2 pb-2.5 text-sm"><input type="checkbox" name="active" defaultChecked={s.active} /> Ativa</label><SubmitButton className="btn btn-sm" pendingText="…">Salvar</SubmitButton></form>))}</div>
        <form action={saveStage.bind(null, null)} className="mt-6 grid items-end gap-3 border-t border-line pt-5 sm:grid-cols-[1fr_6rem_6rem_8rem_auto_auto]"><Field label="Nova etapa"><input name="name" required className="input" /></Field><Field label="Posição"><input name="position" type="number" defaultValue={((stages?.at(-1)?.position ?? 0) + 1)} className="input" /></Field><Field label="Prob. %"><input name="probability" type="number" defaultValue={30} className="input" /></Field>
          <Field label="Tipo"><select name="kind" className="input"><option value="open">Aberta</option><option value="won">Ganho</option><option value="lost">Perdido</option></select></Field><input type="hidden" name="active" value="on" /><SubmitButton className="btn btn-sm btn-dark" pendingText="…">Adicionar</SubmitButton></form></section>

      <section className="card mb-8"><h2 className="mb-4 text-base font-semibold">Integrações</h2>
        <p className="mb-4 text-sm text-muted">Nenhuma integração externa está conectada. Cada linha abaixo está <b>pendente</b>; o sistema só marcará como ativa após uma chamada real bem-sucedida.</p>
        <ul className="divide-y divide-line">{INTEGRATIONS.map((i) => <li key={i.name} className="flex flex-wrap items-center justify-between gap-2 py-3 text-sm"><div><div className="font-medium">{i.name}</div><div className="text-xs text-muted">{i.need}</div></div><span className="flex gap-2"><span className="badge">{i.phase}</span><Pending>Pendente</Pending></span></li>)}</ul></section>

      <section className="card"><h2 className="mb-4 text-base font-semibold">Auditoria recente</h2>
        <table className="w-full text-sm"><tbody>{audit?.map((a) => <tr key={a.id} className="border-b border-line last:border-0"><td className="py-2 text-muted">{dateTimeBR(a.created_at)}</td><td className="py-2">{a.action} em <code>{a.table_name}</code></td><td className="py-2 text-right text-muted">{a.actor_id ? names.get(a.actor_id) ?? 'usuário' : 'sistema'}</td></tr>)}</tbody></table>
        <p className="mt-3 text-xs text-muted">Logado: {profile.email}. A trilha completa fica na tabela <code>audit_log</code> (somente administradores).</p></section>
    </>
  );
}
