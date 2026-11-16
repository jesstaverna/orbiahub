import { redirect } from 'next/navigation';
import { Suspense } from 'react';
import { createClient } from '@/lib/supabase/server';
import { getSession, flash } from '@/lib/session';
import { validatePassword } from '@/lib/password';
import { Flash } from '@/components/Flash';
import { Logo } from '@/components/Logo';
import { SubmitButton } from '@/components/SubmitButton';
import { Field } from '@/components/ui';

export const metadata = { title: 'Definir senha' };

async function setPassword(fd: FormData) {
  'use server';
  const s = await getSession();
  if (!s) redirect('/login');
  const pw = String(fd.get('password') ?? '');
  const bad = validatePassword(pw, String(fd.get('confirm') ?? ''));
  if (bad) flash('/definir-senha', 'err', bad);
  const { error } = await (await createClient()).auth.updateUser({ password: pw });
  if (error) flash('/definir-senha', 'err', 'Não foi possível salvar a senha. Peça um novo link e tente de novo.');
  redirect('/dashboard');
}

export default async function DefinirSenha() {
  const s = await getSession();
  if (!s) redirect('/login');
  return (
    <main className="grid min-h-screen place-items-center px-6">
      <Suspense><Flash /></Suspense>
      <form action={setPassword} className="card w-full max-w-sm space-y-5">
        <Logo className="h-7" />
        <div><h1 className="text-xl font-semibold">Defina sua senha</h1><p className="mt-1.5 text-sm text-muted">Conta: {s.profile.email}. Mínimo de 10 caracteres, com letras e números.</p></div>
        <Field label="Nova senha"><input name="password" type="password" required minLength={10} maxLength={72} autoComplete="new-password" className="input" /></Field>
        <Field label="Repita a senha"><input name="confirm" type="password" required minLength={10} maxLength={72} autoComplete="new-password" className="input" /></Field>
        <SubmitButton className="btn btn-primary w-full" pendingText="Salvando…">Salvar e entrar</SubmitButton>
      </form>
    </main>
  );
}
