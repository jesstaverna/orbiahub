import { redirect } from 'next/navigation';
import { Suspense } from 'react';
import { createClient } from '@/lib/supabase/server';
import { Flash } from '@/components/Flash';
import { SubmitButton } from '@/components/SubmitButton';
import { Field } from '@/components/ui';
import { flash } from '@/lib/session';
import { Logo } from '@/components/Logo';

async function signIn(formData: FormData) {
  'use server';
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email: String(formData.get('email') ?? '').trim(), password: String(formData.get('password') ?? '') });
  if (error) flash('/login', 'err', 'E-mail ou senha inválidos.'); // mensagem genérica: não revela se o e-mail existe
  redirect('/dashboard');
}

async function forgot(formData: FormData) {
  'use server';
  const email = String(formData.get('email') ?? '').trim();
  if (email) await (await createClient()).auth.resetPasswordForEmail(email);   // o e-mail leva a /auth/confirm (template do Supabase)
  // resposta idêntica exista ou não a conta: não revela quem é cliente
  flash('/login', 'ok', 'Se o e-mail estiver cadastrado, enviamos as instruções para redefinir a senha.');
}

export const metadata = { title: 'Entrar' };

export default function LoginPage() {
  return (
    <main className="grid min-h-screen lg:grid-cols-2">
      <Suspense><Flash /></Suspense>
      <section className="hidden flex-col justify-between bg-[#0B0B0F] p-12 text-white lg:flex">
        <div className="flex items-center gap-3"><Logo inverse className="h-9" /></div>
        <div><p className="max-w-md text-4xl font-semibold leading-tight tracking-tight">Sua agência inteira. Um só lugar.</p><p className="mt-4 text-sm text-white/50">CRM, propostas, projetos, anúncios e financeiro conectados.</p></div>
        <span className="h-1.5 w-24 rounded-full bg-brand" />
      </section>
      <section className="flex items-center justify-center px-6 py-16">
        <form action={signIn} className="w-full max-w-sm space-y-5">
          <div className="lg:hidden"><Logo className="h-8" /></div>
          <div><h1 className="h1">Entrar</h1><p className="mt-1.5 text-sm text-muted">Acesso restrito a usuários cadastrados na sua agência.</p></div>
          <Field label="E-mail"><input name="email" type="email" required autoComplete="email" className="input" /></Field>
          <Field label="Senha"><input name="password" type="password" required autoComplete="current-password" className="input" /></Field>
          <SubmitButton className="btn btn-primary w-full" pendingText="Entrando…">Entrar</SubmitButton>
          <button formAction={forgot} formNoValidate className="w-full text-center text-sm text-muted underline">Esqueci a senha (informe o e-mail acima)</button>
        </form>
      </section>
    </main>
  );
}
