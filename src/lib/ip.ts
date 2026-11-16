import 'server-only';
import { headers } from 'next/headers';

/** Primeiro IP de uma lista x-forwarded-for; só aceita IPv4/IPv6 sintaticamente plausíveis (vai para o banco como evidência). */
export function firstIp(xff: string | null | undefined): string | null {
  const ip = (xff ?? '').split(',')[0]?.trim();
  return ip && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : null;
}

/** IP do visitante visto pela plataforma de hospedagem (ex.: Vercel define x-forwarded-for / x-real-ip). */
export async function visitorIp(): Promise<string | null> {
  const h = await headers();
  return firstIp(h.get('x-forwarded-for')) ?? firstIp(h.get('x-real-ip'));
}
