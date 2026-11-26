'use server';
import { revalidatePath } from 'next/cache';
import { flash, requireModule } from '@/lib/session';
import { CLAUSE_CATEGORY_LABEL, SERVICE_TYPE_LABEL, contractError } from '@/lib/contracts';

const BACK = '/contratos/modelos';
const err = (e: { code?: string; message?: string }, what = 'Não foi possível salvar.') =>
  e.code === '23505' ? 'Já existe um item com esse nome.' : e.code === '23503' ? 'Item em uso por modelos: desative em vez de apagar.' : contractError(e, what);

export async function saveClause(id: string | null, fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const title = String(fd.get('title') ?? '').trim(); const body = String(fd.get('body') ?? '').trim();
  const category = String(fd.get('category') ?? 'geral');
  if (!title || !body) flash(`${BACK}?tab=clausulas`, 'err', 'Informe título e texto da cláusula.');
  if (!(category in CLAUSE_CATEGORY_LABEL)) flash(`${BACK}?tab=clausulas`, 'err', 'Categoria inválida.');
  const row = { title, body, category };
  const { error } = id ? await supabase.from('clause_library').update({ ...row, is_starter: false }).eq('id', id) : await supabase.from('clause_library').insert(row);
  if (error) flash(`${BACK}?tab=clausulas`, 'err', err(error));
  revalidatePath(BACK);
  flash(`${BACK}?tab=clausulas`, 'ok', id ? 'Cláusula salva. Contratos já gerados não mudam.' : 'Cláusula criada.');
}
export async function toggleClause(id: string, active: boolean) {
  const { supabase } = await requireModule('contratos');
  await supabase.from('clause_library').update({ active }).eq('id', id);
  revalidatePath(BACK); flash(`${BACK}?tab=clausulas`, 'ok', active ? 'Cláusula reativada.' : 'Cláusula desativada (não entra em novos contratos).');
}
export async function deleteClause(id: string) {
  const { supabase } = await requireModule('contratos');
  const { error } = await supabase.from('clause_library').delete().eq('id', id);
  if (error) flash(`${BACK}?tab=clausulas`, 'err', err(error));
  revalidatePath(BACK); flash(`${BACK}?tab=clausulas`, 'ok', 'Cláusula removida.');
}

export async function saveTemplate(id: string | null, fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const name = String(fd.get('name') ?? '').trim();
  const service_type = String(fd.get('service_type') ?? 'geral');
  if (!name) flash(BACK, 'err', 'Informe o nome do modelo.');
  if (!(service_type in SERVICE_TYPE_LABEL)) flash(BACK, 'err', 'Tipo de serviço inválido.');
  const row = { name, service_type, description: String(fd.get('description') ?? '').trim() || null };
  const { error } = id ? await supabase.from('contract_templates').update({ ...row, is_starter: false }).eq('id', id) : await supabase.from('contract_templates').insert(row);
  if (error) flash(BACK, 'err', err(error));
  revalidatePath(BACK); flash(BACK, 'ok', id ? 'Modelo salvo.' : 'Modelo criado. Adicione as cláusulas.');
}
export async function toggleTemplate(id: string, active: boolean) {
  const { supabase } = await requireModule('contratos');
  await supabase.from('contract_templates').update({ active }).eq('id', id);
  revalidatePath(BACK); flash(BACK, 'ok', active ? 'Modelo reativado.' : 'Modelo desativado.');
}
export async function deleteTemplate(id: string) {
  const { supabase } = await requireModule('contratos');
  const { error } = await supabase.from('contract_templates').delete().eq('id', id);
  if (error) flash(BACK, 'err', err(error));
  revalidatePath(BACK); flash(BACK, 'ok', 'Modelo removido. Contratos já gerados foram mantidos.');
}
export async function duplicateTemplate(id: string) {
  const { supabase } = await requireModule('contratos');
  const [{ data: t }, { data: links }] = await Promise.all([
    supabase.from('contract_templates').select('name, service_type, description').eq('id', id).single(),
    supabase.from('contract_template_clauses').select('clause_id, position').eq('template_id', id).order('position'),
  ]);
  if (!t) flash(BACK, 'err', 'Modelo não encontrado.');
  const { data: copy, error } = await supabase.from('contract_templates').insert({ name: `${t!.name} (cópia)`, service_type: t!.service_type, description: t!.description }).select('id').single();
  if (error || !copy) flash(BACK, 'err', err(error ?? {}, 'Não foi possível duplicar (já existe uma cópia?).'));
  if (links?.length) await supabase.from('contract_template_clauses').insert(links.map((l) => ({ template_id: copy!.id, clause_id: l.clause_id, position: l.position })));
  revalidatePath(BACK); flash(BACK, 'ok', 'Modelo duplicado. Edite a cópia à vontade.');
}

export async function addTemplateClause(templateId: string, fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const clause = String(fd.get('clause') ?? '');
  if (!clause) flash(BACK, 'err', 'Escolha uma cláusula.');
  const { count } = await supabase.from('contract_template_clauses').select('id', { count: 'exact', head: true }).eq('template_id', templateId);
  const { error } = await supabase.from('contract_template_clauses').insert({ template_id: templateId, clause_id: clause, position: (count ?? 0) + 1 });
  if (error) flash(BACK, 'err', error.code === '23505' ? 'Essa cláusula já está no modelo.' : err(error));
  revalidatePath(BACK); flash(BACK, 'ok', 'Cláusula adicionada ao modelo.');
}
export async function removeTemplateClause(linkId: string) {
  const { supabase } = await requireModule('contratos');
  await supabase.from('contract_template_clauses').delete().eq('id', linkId);
  revalidatePath(BACK); flash(BACK, 'ok', 'Cláusula removida do modelo.');
}
export async function moveTemplateClause(templateId: string, linkId: string, dir: 'up' | 'down') {
  const { supabase } = await requireModule('contratos');
  const { data: links } = await supabase.from('contract_template_clauses').select('id').eq('template_id', templateId).order('position');
  const ids = (links ?? []).map((l) => l.id); const i = ids.indexOf(linkId); const j = dir === 'up' ? i - 1 : i + 1;
  if (i < 0 || j < 0 || j >= ids.length) flash(BACK, 'err', 'Não é possível mover nessa direção.');
  [ids[i], ids[j]] = [ids[j], ids[i]];
  // reescreve posições 1..n (a unicidade é por modelo+cláusula, não por posição)
  await Promise.all(ids.map((id, k) => supabase.from('contract_template_clauses').update({ position: k + 1 }).eq('id', id)));
  revalidatePath(BACK); flash(BACK, 'ok', 'Ordem atualizada.');
}
