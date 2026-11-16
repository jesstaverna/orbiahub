/** Regra de MFA (TOTP) para contas privilegiadas — função pura, usada pelo servidor em toda página protegida. */
export type MfaStep = 'challenge' | 'enroll' | null;

export function mfaNextStep(o: { privileged: boolean; current: string | null; next: string | null; required: boolean }): MfaStep {
  // já tem fator verificado e a sessão ainda é aal1 → pedir o código (vale para qualquer usuário que ativou MFA)
  if (o.next === 'aal2' && o.current !== 'aal2') return 'challenge';
  // sem fator: só obriga quem é privilegiado e quando a política exige (REQUIRE_MFA_ADMIN=true)
  if (o.required && o.privileged && o.next !== 'aal2') return 'enroll';
  return null;
}

export const isPrivileged = (p: { role: string; is_platform_admin: boolean }) => p.role === 'admin' || p.is_platform_admin;
export const mfaRequired = () => process.env.REQUIRE_MFA_ADMIN === 'true';
export const mfaPath = (step: MfaStep) => (step === 'challenge' ? '/mfa' : step === 'enroll' ? '/seguranca?obrigatorio=1' : null);
