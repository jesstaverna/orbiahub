import { createBrowserClient } from '@supabase/ssr';

/** Cliente do navegador (usa os cookies da sessão). Só para o MFA, que precisa do QR/código no cliente. Nunca usa chave de serviço. */
export const createBrowserSupabase = () => createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
