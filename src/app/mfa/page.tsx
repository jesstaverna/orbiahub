import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getSession } from '@/lib/session';
import { Logo } from '@/components/Logo';
import { MfaChallenge } from '@/components/Mfa';

export const metadata = { title: 'Verificação em duas etapas' };

async function signOut() { 'use server'; await (await createClient()).auth.signOut(); redirect('/login'); }

export default async function Mfa() {
  const s = await getSession();
  if (!s) redirect('/login');
  if (s.mfa !== '/mfa') redirect('/dashboard');
  const { data } = await (await createClient()).auth.mfa.listFactors();
  const factor = data?.totp?.find((f) => f.status === 'verified');
  if (!factor) redirect('/dashboard');
  return (
    <main className="grid min-h-screen place-items-center px-6">
      <div className="card w-full max-w-sm space-y-5">
        <Logo className="h-7" />
        <div><h1 className="text-xl font-semibold">Confirme que é você</h1><p className="mt-1.5 text-sm text-muted">Digite o código de 6 dígitos do seu app autenticador.</p></div>
        <MfaChallenge factorId={factor.id} />
        <form action={signOut}><button className="btn btn-sm w-full">Sair</button></form>
      </div>
    </main>
  );
}
