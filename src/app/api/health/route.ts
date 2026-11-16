import { NextResponse } from 'next/server';

/** Health check para monitoramento de disponibilidade (UptimeRobot/BetterStack). Não expõe dados. */
export function GET() {
  return NextResponse.json({ ok: true, service: 'orbiahub', time: new Date().toISOString() });
}
