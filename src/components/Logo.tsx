/* Logo orbiahub.: versão principal no claro, inversa no escuro (troca pelo tema, sem JS). Arquivos em public/brand. */
export function Logo({ className = 'h-7', inverse = false }: { className?: string; inverse?: boolean }) {
  if (inverse) return <img src="/brand/logo-inverse.webp" alt="orbiahub." className={`${className} w-auto`} />;
  return (
    <>
      <img src="/brand/logo.webp" alt="orbiahub." className={`${className} w-auto dark:hidden`} />
      <img src="/brand/logo-inverse.webp" alt="orbiahub." className={`${className} hidden w-auto dark:block`} />
    </>
  );
}
