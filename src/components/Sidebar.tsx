'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Menu, X } from 'lucide-react';
import { useState } from 'react';
import { Icon } from './Icon';
import { Logo } from './Logo';

export interface NavItem { key: string; label: string; href: string; icon: string; phase: number }

export function Sidebar({ items, userName, roleLabel, agencyName, isPlatformAdmin, signOut }: { items: NavItem[]; userName: string; roleLabel: string; agencyName: string; isPlatformAdmin: boolean; signOut: () => Promise<void> }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  const nav = (
    <nav aria-label="Menu principal" className="flex-1 space-y-0.5 overflow-y-auto px-3 py-2">
      {items.map((m) => {
        const active = pathname === m.href || pathname.startsWith(m.href + '/');
        return (
          <Link key={m.key} href={m.href} onClick={() => setOpen(false)} aria-current={active ? 'page' : undefined}
            className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm transition ${active ? 'bg-brand font-medium text-on-brand' : 'text-fg/80 hover:bg-subtle'}`}>
            <Icon name={m.icon} />
            <span className="flex-1">{m.label}</span>
            {m.phase > 1 && <span className="rounded-full border border-current px-1.5 text-[10px] opacity-60">F{m.phase}</span>}
          </Link>
        );
      })}
      {isPlatformAdmin && (
        <Link href="/plataforma" onClick={() => setOpen(false)} className="mt-3 flex items-center gap-3 rounded-xl border border-dashed border-line px-3 py-2.5 text-sm text-fg/80 transition hover:bg-subtle">
          <Icon name="settings" /><span className="flex-1">Plataforma</span>
        </Link>
      )}
    </nav>
  );

  const brand = (
    <div className="flex items-center gap-2.5 px-6 pb-4 pt-6">
      <div className="min-w-0 space-y-1.5"><Logo className="h-7" /><div className="truncate text-[11px] text-muted" title={agencyName}>{agencyName}</div></div>
    </div>
  );

  const footer = (
    <div className="border-t border-line p-4">
      <div className="truncate text-sm font-medium">{userName}</div>
      <div className="mb-3 text-xs text-muted">{roleLabel}</div>
      <form action={signOut}><button className="btn btn-sm w-full">Sair</button></form>
    </div>
  );

  return (
    <>
      <div className="fixed inset-x-0 top-0 z-30 flex items-center justify-between border-b border-line bg-bg/90 px-4 py-3 backdrop-blur lg:hidden">
        <span className="flex items-center gap-2"><Logo className="h-5" /><span className="text-xs text-muted">· {agencyName}</span></span>
        <button onClick={() => setOpen(true)} aria-label="Abrir menu" className="btn btn-sm"><Menu className="h-4 w-4" /></button>
      </div>
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-64 flex-col border-r border-line bg-surface lg:flex">{brand}{nav}{footer}</aside>
      {open && (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal>
          <div className="absolute inset-0 bg-black/50" onClick={() => setOpen(false)} />
          <aside className="absolute inset-y-0 left-0 flex w-72 max-w-[85vw] flex-col bg-surface">
            <button onClick={() => setOpen(false)} aria-label="Fechar menu" className="btn btn-sm absolute right-3 top-3"><X className="h-4 w-4" /></button>
            {brand}{nav}{footer}
          </aside>
        </div>
      )}
    </>
  );
}
