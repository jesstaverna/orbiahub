'use server';
import { revalidatePath } from 'next/cache';
import { flash, requireModule } from '@/lib/session';
import { CATEGORIES, parseBRL, splitLines } from '@/lib/catalog';

const BACK = '/catalogo';
const dbErr = (code?: string, what = 'Não foi possível salvar.') =>
  code === '23505' ? 'Já existe um item com esse nome.' : code === '23514' ? 'Valor ou categoria inválidos.' : code === '23503' ? 'Este serviço está em um pacote: remova-o do pacote ou apenas desative.' : code === '42501' ? 'Seu perfil não pode gerenciar o catálogo.' : what;

export async function saveService(id: string | null, fd: FormData) {
  const { supabase } = await requireModule('catalogo');
  const name = String(fd.get('name') ?? '').trim();
  if (!name) flash(BACK, 'err', 'Informe o nome do serviço.');
  const category = String(fd.get('category') ?? 'outro');
  const price = parseBRL(fd.get('unit_price'));
  if (!CATEGORIES.includes(category) || price < 0) flash(BACK, 'err', 'Categoria ou valor inválidos.');
  const row = {
    name, category, billing: fd.get('billing') === 'mensal' ? 'mensal' : 'pontual', unit_price: price,
    description: String(fd.get('description') ?? '').trim() || null, deliverables: splitLines(fd.get('deliverables')),
  };
  const { error } = id ? await supabase.from('service_catalog').update(row).eq('id', id) : await supabase.from('service_catalog').insert(row);
  if (error) flash(BACK, 'err', dbErr(error.code));
  revalidatePath(BACK);
  flash(BACK, 'ok', id ? 'Serviço atualizado. Propostas já montadas não mudam.' : 'Serviço criado.');
}

export async function toggleService(id: string, active: boolean) {
  const { supabase } = await requireModule('catalogo');
  const { error } = await supabase.from('service_catalog').update({ active }).eq('id', id);
  if (error) flash(BACK, 'err', dbErr(error.code));
  revalidatePath(BACK);
  flash(BACK, 'ok', active ? 'Serviço reativado.' : 'Serviço desativado (não entra em novas propostas).');
}

export async function deleteService(id: string) {
  const { supabase } = await requireModule('catalogo');
  const { error } = await supabase.from('service_catalog').delete().eq('id', id);
  if (error) flash(BACK, 'err', dbErr(error.code));
  revalidatePath(BACK);
  flash(BACK, 'ok', 'Serviço removido. Itens de propostas existentes foram mantidos.');
}

export async function savePackage(id: string | null, fd: FormData) {
  const { supabase } = await requireModule('catalogo');
  const name = String(fd.get('name') ?? '').trim();
  if (!name) flash(`${BACK}?tab=pacotes`, 'err', 'Informe o nome do pacote.');
  const row = { name, description: String(fd.get('description') ?? '').trim() || null };
  const { error } = id ? await supabase.from('packages').update(row).eq('id', id) : await supabase.from('packages').insert(row);
  if (error) flash(`${BACK}?tab=pacotes`, 'err', dbErr(error.code));
  revalidatePath(BACK);
  flash(`${BACK}?tab=pacotes`, 'ok', id ? 'Pacote atualizado.' : 'Pacote criado. Adicione os serviços dele.');
}

export async function togglePackage(id: string, active: boolean) {
  const { supabase } = await requireModule('catalogo');
  await supabase.from('packages').update({ active }).eq('id', id);
  revalidatePath(BACK);
  flash(`${BACK}?tab=pacotes`, 'ok', active ? 'Pacote reativado.' : 'Pacote desativado.');
}

export async function deletePackage(id: string) {
  const { supabase } = await requireModule('catalogo');
  const { error } = await supabase.from('packages').delete().eq('id', id);
  if (error) flash(`${BACK}?tab=pacotes`, 'err', dbErr(error.code));
  revalidatePath(BACK);
  flash(`${BACK}?tab=pacotes`, 'ok', 'Pacote removido.');
}

export async function addPackageItem(packageId: string, fd: FormData) {
  const { supabase } = await requireModule('catalogo');
  const service = String(fd.get('service') ?? '');
  if (!service) flash(`${BACK}?tab=pacotes`, 'err', 'Escolha um serviço.');
  const raw = String(fd.get('price') ?? '').trim();
  const { count } = await supabase.from('package_items').select('id', { count: 'exact', head: true }).eq('package_id', packageId);
  const { error } = await supabase.from('package_items').insert({
    package_id: packageId, service_id: service, quantity: Number(fd.get('quantity') ?? 1) || 1,
    unit_price_override: raw ? parseBRL(raw) : null, position: count ?? 0,
  });
  if (error) flash(`${BACK}?tab=pacotes`, 'err', error.code === '23505' ? 'Esse serviço já está no pacote.' : dbErr(error.code));
  revalidatePath(BACK);
  flash(`${BACK}?tab=pacotes`, 'ok', 'Serviço adicionado ao pacote.');
}

export async function removePackageItem(itemId: string) {
  const { supabase } = await requireModule('catalogo');
  await supabase.from('package_items').delete().eq('id', itemId);
  revalidatePath(BACK);
  flash(`${BACK}?tab=pacotes`, 'ok', 'Serviço removido do pacote.');
}
