'use server';
import { revalidatePath } from 'next/cache';
import { flash, requireModule } from '@/lib/session';
import { contractError, sectionsFromForm } from '@/lib/contracts';
import { parseBRL } from '@/lib/catalog';

const back = (id: string) => `/contratos/${id}`;
const num = (v: FormDataEntryValue | null) => parseBRL(v);

export async function generateContract(fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const template = String(fd.get('template') ?? '');
  const proposal = String(fd.get('proposal') ?? '') || null;
  const client = String(fd.get('client') ?? '') || null;
  if (!template) flash('/contratos/novo', 'err', 'Escolha um modelo.');
  if (!proposal && !client) flash('/contratos/novo', 'err', 'Escolha uma proposta aceita ou um cliente.');
  const start = String(fd.get('start') ?? '') || null;
  const title = String(fd.get('title') ?? '').trim() || null;
  const { data, error } = await supabase.rpc('contract_generate', { p_template: template, p_proposal: proposal, p_client: proposal ? null : client, p_start: start, p_title: title });
  if (error) flash(proposal ? `/contratos/novo?proposal=${proposal}` : '/contratos/novo', 'err', contractError(error, 'Não foi possível gerar o contrato.'));
  revalidatePath('/contratos');
  flash(back(String(data)), 'ok', 'Rascunho gerado. Revise cada cláusula e preencha os [CAMPO A PREENCHER] antes de enviar para revisão.');
}

export async function saveContract(id: string, fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const content = sectionsFromForm(fd.getAll('s_title').map(String), fd.getAll('s_body').map(String));
  if (!content.length) flash(back(id), 'err', 'O contrato precisa ter ao menos uma cláusula.');
  const start = String(fd.get('start_date') ?? '') || null;
  const end = String(fd.get('end_date') ?? '') || null;
  const row = {
    title: String(fd.get('title') ?? '').trim(), content, start_date: start, end_date: end, auto_renew: fd.get('auto_renew') === 'on',
    renewal_notice_days: Math.min(Math.max(Math.round(Number(fd.get('renewal_notice_days') ?? 30)) || 0, 0), 365),
    monthly_value: num(fd.get('monthly_value')), one_time_value: num(fd.get('one_time_value')), total_value: num(fd.get('total_value')),
    payment_terms: String(fd.get('payment_terms') ?? '').trim(),
  };
  if (!row.title) flash(back(id), 'err', 'Informe o título do contrato.');
  const { data, error } = await supabase.from('contracts').update(row).eq('id', id).select('id');
  if (error) flash(back(id), 'err', contractError(error, 'Não foi possível salvar. Verifique as datas.'));
  if (!data?.length) flash(back(id), 'err', 'Contrato não encontrado ou sem permissão para editar.');
  revalidatePath(back(id));
  flash(back(id), 'ok', 'Contrato salvo.');
}

async function transition(id: string, patch: Record<string, unknown>, ok: string, snapshotNote?: string) {
  const { supabase } = await requireModule('contratos');
  const { data, error } = await supabase.from('contracts').update(patch).eq('id', id).select('id');
  if (error) flash(back(id), 'err', contractError(error));
  if (!data?.length) flash(back(id), 'err', 'Contrato não encontrado ou sem permissão.');
  if (snapshotNote) await supabase.rpc('contract_snapshot', { p_id: id, p_note: snapshotNote });
  revalidatePath(back(id)); revalidatePath('/contratos');
  flash(back(id), 'ok', ok);
}

export const sendToReview = async (id: string) => transition(id, { status: 'em_revisao' }, 'Enviado para revisão.', 'Enviado para revisão');
export const backToDraft = async (id: string) => transition(id, { status: 'rascunho' }, 'Voltou para rascunho.');
export const backToReview = async (id: string) => transition(id, { status: 'em_revisao' }, 'Voltou para revisão: a aprovação anterior foi anulada.');
export const closeContract = async (id: string) => transition(id, { status: 'encerrado' }, 'Contrato encerrado.');

export async function approveContract(id: string, fd: FormData) {
  if (fd.get('confirm') !== 'on') flash(back(id), 'err', 'Confirme que o contrato foi revisado.');
  await transition(id, { status: 'aguardando_assinatura', review_confirmed: true }, 'Aprovado. O conteúdo foi travado e está pronto para assinatura (fora do sistema).', 'Aprovado para assinatura');
}

export async function registerSignature(id: string, fd: FormData) {
  await transition(id, { status: 'assinado', signature_note: String(fd.get('note') ?? '').trim() }, 'Assinatura registrada (feita fora do sistema).', 'Assinatura registrada');
}

export async function cancelContract(id: string, fd: FormData) {
  await transition(id, { status: 'cancelado', cancelled_reason: String(fd.get('reason') ?? '').trim() }, 'Contrato cancelado.');
}

export async function saveSnapshot(id: string, fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const { error } = await supabase.rpc('contract_snapshot', { p_id: id, p_note: String(fd.get('note') ?? '').trim() || null });
  if (error) flash(back(id), 'err', contractError(error));
  revalidatePath(back(id));
  flash(back(id), 'ok', 'Versão salva no histórico.');
}

export async function renewContract(id: string, fd: FormData) {
  const { supabase } = await requireModule('contratos');
  const { data, error } = await supabase.rpc('contract_renew', { p_id: id, p_months: Math.round(Number(fd.get('months') ?? 0)) });
  if (error) flash(back(id), 'err', contractError(error, 'Não foi possível renovar.'));
  revalidatePath(back(id));
  flash(back(id), 'ok', `Vigência prorrogada até ${String(data).split('-').reverse().join('/')}. Confirme as condições com o cliente.`);
}

export async function deleteDraft(id: string) {
  const { supabase } = await requireModule('contratos');
  const { data } = await supabase.from('contracts').delete().eq('id', id).select('id');
  if (!data?.length) flash(back(id), 'err', 'Só rascunhos podem ser apagados.');
  revalidatePath('/contratos');
  flash('/contratos', 'ok', 'Rascunho apagado.');
}
