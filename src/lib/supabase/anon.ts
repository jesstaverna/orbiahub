import { createClient as create } from '@supabase/supabase-js';

/**
 * Cliente anônimo sem sessão — só para as RPCs públicas (link de proposta). Nunca tem acesso direto a tabelas.
 * `ip` = IP do visitante: o banco o grava como evidência do aceite e o usa no limite de requisições
 * (sem isso ele veria apenas o IP do servidor do app).
 */
export function createAnonClient(ip?: string | null) {
  return create(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: ip ? { headers: { 'x-client-ip': ip } } : undefined,
  });
}
