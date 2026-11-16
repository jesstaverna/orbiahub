import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/lib/supabase/server';

const TYPES = ['invite', 'recovery', 'magiclink', 'email', 'signup'] as const;
type OtpType = (typeof TYPES)[number];

/**
 * Destino dos e-mails de convite e de redefinição de senha (template do Supabase aponta para cá, com token_hash).
 * Troca o token por uma sessão e leva a /definir-senha. Ver docs/DEPLOY.md §2.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const base = process.env.NEXT_PUBLIC_APP_URL || origin;
  const tokenHash = searchParams.get('token_hash');
  const type = searchParams.get('type') as OtpType | null;
  const fail = () => NextResponse.redirect(new URL(`/login?err=${encodeURIComponent('Link inválido ou expirado. Peça um novo convite ou use “Esqueci a senha”.')}`, base));
  if (!tokenHash || !type || !TYPES.includes(type)) return fail();

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
  if (error) return fail();
  return NextResponse.redirect(new URL(type === 'invite' || type === 'recovery' ? '/definir-senha' : '/dashboard', base));
}
