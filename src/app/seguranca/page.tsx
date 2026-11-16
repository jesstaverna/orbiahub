import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { getSession } from '@/lib/session';
import { mfaRequired } from '@/lib/mfa';
import { Logo } from '@/components/Logo';
import { MfaDisable, MfaEnroll } from '@/components/Mfa';

export const metadata = { title: 'Segurança da conta' };

export default async function Seguranca({ searchParams }: { searchParams: Promise<{ obrigatorio?: string }> }) {
  const s = await getSession();
  if (!s) redirect('/login');
  if (s.mfa === '/mfa') redirect('/mfa');   // tem fator, falta o código
  const { data } = await (await createClient()).auth.mfa.listFactors();
  const factor = data?.totp?.find((f) => f.status === 'verified');
  const sp = await searchParams;
  return (
    <main className="mx-auto max-w-md px-6 py-14">
      <Logo className="mb-8 h-7" />
      <h1 className="text-xl font-semibold">Verificação em duas etapas</h1>
      <p className="mb-6 mt-1.5 text-sm text-muted">Protege sua conta com um código do app autenticador, além da senha. Recomendado para administradores.</p>
      {sp.obrigatorio && !factor && <p className="mb-6 rounded-xl border border-line bg-subtle p-4 text-sm">Sua agência exige a verificação em duas etapas para administradores. Ative para continuar.</p>}
      <div className="card">
        {factor ? (
          <div className="space-y-4"><p className="text-sm"><b>Ativa.</b> Sua conta pede o código a cada novo login.</p>
            {mfaRequired() && s.profile.role === 'admin' ? <p className="text-xs text-muted">A política da plataforma não permite desativar para administradores.</p> : <MfaDisable factorId={factor.id} />}</div>
        ) : <MfaEnroll />}
      </div>
      {(factor || !mfaRequired()) && <p className="mt-6 text-sm"><Link href="/dashboard" className="underline">Voltar ao sistema</Link></p>}
    </main>
  );
}
