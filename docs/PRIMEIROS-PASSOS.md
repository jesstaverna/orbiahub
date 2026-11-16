# Primeiros passos — colocar o orbiahub. no ar

Tempo estimado: 20–30 min. Você não precisa saber programar; só copiar e colar.

## 1. Criar o projeto no Supabase
1. Acesse https://supabase.com → **New project** (anote a senha do banco; você não vai precisar dela no app).
2. Escolha a região **South America (São Paulo)**.

## 2. Criar as tabelas
> **Se o seu Supabase já está conectado ao GitHub** (Project Settings → Integrations → GitHub), ele aplica `supabase/migrations/` sozinho quando este PR for mesclado na branch de produção configurada — **pule este passo** e confira em *Table Editor* se as tabelas apareceram. Não rode o `setup.sql` além disso (duplicaria objetos e daria erro).

Caminho manual:
1. No projeto: **SQL Editor → New query**.
2. Abra o arquivo `supabase/setup.sql` deste repositório, copie **tudo**, cole e clique em **Run**.
3. Deve terminar com "Success". (Rode **uma vez só**, em projeto vazio.)

## 3. Segurança do login
- **Authentication → Providers → Email**: desative **"Allow new users to sign up"** (usuários só por convite).
- **Authentication → URL Configuration**: em *Site URL* coloque o endereço do app (ex.: `http://localhost:3000` por enquanto).

## 4. Criar seu usuário (administrador da plataforma)
- **Authentication → Users → Add user → Create new user**: e-mail + senha, marque *Auto Confirm User*.
- O **primeiro** usuário criado vira **administrador da plataforma** (cria agências e planos; não vê os dados delas). Os próximos entram **sem agência**, sem acesso a nada, até serem vinculados.
- Depois de logar você cai em **/plataforma**: crie a sua agência com o seu e-mail como proprietário. A partir daí a equipe é adicionada em *Configurações → Usuários*.

## 5. Pegar as chaves
**Project Settings → API**:
- `Project URL` → `NEXT_PUBLIC_SUPABASE_URL`
- `anon public` → `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `service_role` → `SUPABASE_SERVICE_ROLE_KEY` (**secreta**: só no servidor/Vercel, nunca em chat, e-mail ou código)

## 6. Rodar
**No seu computador** (precisa de Node 20+):
```bash
cp .env.example .env.local     # preencha as 3 chaves acima + CRON_SECRET (qualquer texto longo e aleatório)
npm install
npm run dev                    # abra http://localhost:3000
```
**Ou na Vercel**: importe o repositório, cadastre as mesmas variáveis (`NEXT_PUBLIC_APP_URL` = URL final) e faça o deploy. Depois atualize a *Site URL* do passo 3.

## 7. Conferir que funcionou
- [ ] Login com o usuário do passo 4 abre **/plataforma**; criar a agência leva você ao Dashboard dela.
- [ ] **Configurações** lista você como Administrador e mostra o plano/uso.
- [ ] **CRM → Novo lead**: cadastre um lead; tentar cadastrar o mesmo e-mail de novo deve ser bloqueado.
- [ ] **Propostas → Nova proposta**: defina valores, "Marcar como enviada", abra o link `/p/...` em aba anônima e aceite.
- [ ] **Automações** mostra "Última varredura" depois que o agendador (docs/DEPLOY.md §3) rodar.

## Se algo der errado
Copie a mensagem de erro (sem chaves!) e me envie.
