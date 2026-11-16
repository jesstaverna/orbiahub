'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createBrowserSupabase } from '@/lib/supabase/browser';

const Err = ({ msg }: { msg: string | null }) => (msg ? <p role="alert" className="rounded-xl border border-danger/40 bg-danger/10 p-3 text-sm text-danger">{msg}</p> : null);

/** Cadastro do autenticador (TOTP): gera QR, confirma com o primeiro código. */
export function MfaEnroll() {
  const router = useRouter();
  const [f, setF] = useState<{ id: string; qr: string; secret: string } | null>(null);
  const [code, setCode] = useState(''); const [err, setErr] = useState<string | null>(null); const [busy, setBusy] = useState(false);

  async function start() {
    setBusy(true); setErr(null);
    const sb = createBrowserSupabase();
    const { data: list } = await sb.auth.mfa.listFactors();
    for (const x of list?.all ?? []) if (x.status !== 'verified') await sb.auth.mfa.unenroll({ factorId: x.id }); // limpa tentativas antigas
    const { data, error } = await sb.auth.mfa.enroll({ factorType: 'totp', friendlyName: `orbiahub-${Date.now()}` });
    setBusy(false);
    if (error || !data) return setErr('Não foi possível iniciar o cadastro. Tente novamente.');
    setF({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
  }
  async function confirm(e: React.FormEvent) {
    e.preventDefault(); if (!f) return; setBusy(true); setErr(null);
    const { error } = await createBrowserSupabase().auth.mfa.challengeAndVerify({ factorId: f.id, code: code.trim() });
    setBusy(false);
    if (error) return setErr('Código inválido ou expirado. Confira o horário do celular e tente de novo.');
    router.push('/dashboard'); router.refresh();
  }
  if (!f) return <div className="space-y-3"><Err msg={err} /><button onClick={start} disabled={busy} className="btn btn-primary">{busy ? 'Preparando…' : 'Ativar verificação em duas etapas'}</button></div>;
  return (
    <form onSubmit={confirm} className="space-y-4">
      <p className="text-sm">1. Abra um app autenticador (Google Authenticator, 1Password, Authy…) e escaneie o QR.</p>
      <img src={f.qr} alt="QR code do autenticador" className="h-44 w-44 rounded-xl border border-line bg-white p-2" />
      <p className="text-xs text-muted">Sem câmera? Digite a chave: <code className="break-all">{f.secret}</code></p>
      <label className="block"><span className="label">2. Código de 6 dígitos</span>
        <input value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} inputMode="numeric" autoComplete="one-time-code" required className="input max-w-[12rem] tracking-[0.3em]" /></label>
      <Err msg={err} />
      <button disabled={busy || code.length !== 6} className="btn btn-primary">{busy ? 'Verificando…' : 'Confirmar e ativar'}</button>
    </form>
  );
}

/** Pede o código quando a conta tem MFA e a sessão ainda está em aal1. */
export function MfaChallenge({ factorId }: { factorId: string }) {
  const router = useRouter();
  const [code, setCode] = useState(''); const [err, setErr] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  async function submit(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setErr(null);
    const { error } = await createBrowserSupabase().auth.mfa.challengeAndVerify({ factorId, code: code.trim() });
    setBusy(false);
    if (error) return setErr('Código inválido ou expirado.');
    router.push('/dashboard'); router.refresh();
  }
  return (
    <form onSubmit={submit} className="space-y-4">
      <label className="block"><span className="label">Código do autenticador</span>
        <input value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} inputMode="numeric" autoComplete="one-time-code" autoFocus required className="input tracking-[0.3em]" /></label>
      <Err msg={err} />
      <button disabled={busy || code.length !== 6} className="btn btn-primary w-full">{busy ? 'Verificando…' : 'Entrar'}</button>
    </form>
  );
}

export function MfaDisable({ factorId }: { factorId: string }) {
  const router = useRouter(); const [err, setErr] = useState<string | null>(null);
  async function off() {
    if (!confirm('Desativar a verificação em duas etapas? Sua conta fica menos protegida.')) return;
    const { error } = await createBrowserSupabase().auth.mfa.unenroll({ factorId });
    if (error) return setErr('Não foi possível desativar.');
    router.refresh();
  }
  return <div className="space-y-3"><Err msg={err} /><button onClick={off} className="btn btn-danger btn-sm">Desativar</button></div>;
}
