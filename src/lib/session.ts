import { cache } from 'react';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { canAccess, type ModuleKey } from '@/lib/permissions';
import { isPrivileged, mfaNextStep, mfaPath, mfaRequired } from '@/lib/mfa';

export interface Profile {
  id: string; full_name: string; email: string | null; role: string; client_id: string | null; active: boolean;
  agency_id: string | null; is_platform_admin: boolean;
}
export interface Agency { id: string; name: string; slug: string; plan: string; status: string; brand: { primary?: string } }

/**
 * Sessão = usuário + perfil + agência. `agency` é null quando o usuário não tem agência OU ela está suspensa
 * (a RLS só devolve a agência do usuário se ela estiver ativa).
 */
export const getSession = cache(async () => {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) return null;
  const { data: profile } = await supabase.from('profiles')
    .select('id, full_name, email, role, client_id, active, agency_id, is_platform_admin').eq('id', data.user.id).single();
  if (!profile) return null;
  let agency: Agency | null = null;
  if (profile.agency_id) {
    const { data: a } = await supabase.from('agencies').select('id, name, slug, plan, status, brand').eq('id', profile.agency_id).maybeSingle();
    agency = (a as Agency | null) ?? null;
  }
  // papel → permissões (tabela roles da agência; a RLS só mostra os da própria agência)
  let permissions: string[] = []; let roleName = profile.role;
  if (profile.agency_id && agency) {
    const { data: r } = await supabase.from('roles').select('name, permissions').eq('agency_id', profile.agency_id).eq('key', profile.role).maybeSingle();
    permissions = (r?.permissions as string[] | undefined) ?? []; roleName = r?.name ?? roleName;
  }
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();   // lê o JWT local, sem rede
  const mfa = mfaPath(mfaNextStep({ privileged: isPrivileged({ canManage: permissions.includes('settings.manage'), is_platform_admin: profile.is_platform_admin }), current: aal?.currentLevel ?? null, next: aal?.nextLevel ?? null, required: mfaRequired() }));
  return { user: data.user, profile: profile as Profile, agency, mfa, permissions, roleName };
});

export function flash(path: string, kind: 'ok' | 'err', message: string): never {
  const sep = path.includes('?') ? '&' : '?';
  redirect(`${path}${sep}${kind}=${encodeURIComponent(message)}`);
}

/** Exige login, agência ativa e acesso ao módulo. Usar no topo de cada página/ação do módulo. */
export async function requireModule(key: ModuleKey) {
  const s = await getSession();
  if (!s) redirect('/login');
  if (s.mfa) redirect(s.mfa);
  if (!s.profile.active || !s.agency || !s.permissions.includes('app.access')) redirect(s.profile.is_platform_admin && !s.agency ? '/plataforma' : '/sem-acesso');
  if (!canAccess(s.permissions, key)) flash('/dashboard', 'err', 'Seu perfil não tem acesso a este módulo.');
  const permissions = s.permissions;
  return { supabase: await createClient(), ...s, agency: s.agency, can: (permission: string) => permissions.includes(permission) };
}

/** Área da plataforma (gestão de agências e planos). Não dá acesso a dados de negócio das agências. */
export async function requirePlatform() {
  const s = await getSession();
  if (!s) redirect('/login');
  if (s.mfa) redirect(s.mfa);
  if (!s.profile.active || !s.profile.is_platform_admin) redirect('/sem-acesso');
  return { supabase: await createClient(), ...s };
}
