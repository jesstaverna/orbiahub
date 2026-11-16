/** Política de senha (convite / redefinição). Mínimo 10 caracteres, com letra e número, sem sequências triviais. */
const COMMON = ['1234567890', 'senha12345', 'password123', 'qwerty1234', 'abcdefghij1', 'orbiahub123'];

export function validatePassword(pw: string, confirm?: string): string | null {
  if (pw.length < 10) return 'A senha precisa ter pelo menos 10 caracteres.';
  if (pw.length > 72) return 'A senha pode ter no máximo 72 caracteres.';
  if (!/[A-Za-z]/.test(pw) || !/\d/.test(pw)) return 'Use letras e números na senha.';
  if (/^(.)\1+$/.test(pw) || COMMON.includes(pw.toLowerCase())) return 'Essa senha é muito previsível. Escolha outra.';
  if (confirm !== undefined && pw !== confirm) return 'As senhas não conferem.';
  return null;
}
