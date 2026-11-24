'use server';

import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { requireModule, flash } from '@/lib/session';

const schema = z.object({
  name: z.string().trim().min(1).max(100),
  segment: z.string().trim().max(120),
  tone_of_voice: z.string().trim().max(4000),
  primary_color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  secondary_color: z.string().regex(/^#[0-9a-fA-F]{6}$/),
  client_id: z.union([z.literal(''), z.string().uuid()]),
});
export async function saveBrand(form: FormData) {
  const { supabase, can } = await requireModule('brand');
  if (!can('settings.manage')) flash('/brand', 'err', 'Você não tem permissão para editar marcas.');
  const parsed = schema.safeParse(Object.fromEntries(['name','segment','tone_of_voice','primary_color','secondary_color','client_id'].map(key => [key, form.get(key) ?? ''])));
  if (!parsed.success) flash('/brand', 'err', 'Confira os campos e tente novamente.');
  const id = form.get('id');
  if (id && !z.string().uuid().safeParse(id).success) flash('/brand', 'err', 'Marca inválida.');
  const payload = { ...parsed.data, client_id: parsed.data.client_id || null };
  const result = id
    ? await supabase.from('marketing_brands').update(payload).eq('id', String(id)).select('id').single()
    : await supabase.from('marketing_brands').insert(payload).select('id').single();
  if (result.error || !result.data) flash('/brand', 'err', result.error?.code === '23505' ? 'Já existe uma marca com esse nome.' : 'Não foi possível salvar a marca.');
  revalidatePath('/brand');
  flash('/brand', 'ok', 'Marca salva.');
}

export async function setBrandActive(form: FormData) {
  const { supabase, can } = await requireModule('brand');
  if (!can('settings.manage')) flash('/brand', 'err', 'Você não tem permissão para editar marcas.');
  const id = z.string().uuid().safeParse(form.get('id'));
  const active = z.enum(['true','false']).safeParse(form.get('active'));
  if (!id.success || !active.success) flash('/brand', 'err', 'Solicitação inválida.');
  const { data, error } = await supabase.from('marketing_brands').update({active: active.data === 'true'}).eq('id', id.data).select('id').single();
  if (error || !data) flash('/brand', 'err', 'Não foi possível alterar a situação da marca.');
  revalidatePath('/brand');
  flash('/brand', 'ok', 'Situação da marca atualizada.');
}
