#!/usr/bin/env bash
# Valida migrações + regras de negócio/RLS em PostgreSQL local descartável (sem Supabase). Cenários:
#  1. base      : migrações 0001–0005 + suíte original (single-tenant)
#  2. tenant    : 0001–0006 + suíte original sob RLS por agência + isolamento entre agências
#  3. legado    : dados existentes (0001–0005) → 0006 → verificação → rollback → verificação
#  4. rollback  : 0001–0010 em banco vazio → rollback 0010 a 0006 → suíte original
# Uso: supabase/tests/run_local.sh   (requer PostgreSQL 16 e permissão para iniciar o cluster)
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
cd "$(dirname "$0")/.."
psql() { if [ -z "${CI_PG:-}" ] && [ "$(id -u)" = 0 ]; then runuser -u postgres -- env PGDATABASE="${PGDATABASE:-postgres}" psql "$@"; else command psql "$@"; fi; }
if [ -z "${CI_PG:-}" ]; then (pg_lsclusters | grep -q online) || pg_ctlcluster 16 main start; sleep 2; fi
newdb() { PGDATABASE=postgres psql -qAt -c "drop database if exists $1 with (force)" -c "create database $1" >/dev/null; export PGDATABASE=$1; psql -q -v ON_ERROR_STOP=1 < tests/local_stub.sql; }
run() { psql -q -o /dev/null -v ON_ERROR_STOP=1 < "$1"; }
mig() { for f in "$@"; do psql -q -v ON_ERROR_STOP=1 < "$f"; done; }
BASE=(migrations/20261009*.sql); UP=migrations/20261116000006_multitenancy.sql; DOWN=rollback/20261116000006_multitenancy.down.sql
UP7=migrations/20261116000007_public_link_hardening.sql; UP8=migrations/20261116000008_roles_permissions.sql; DOWN7=rollback/20261116000007_public_link_hardening.down.sql; UP9=migrations/20261116000009_service_catalog.sql; UP10=migrations/20261116000010_contracts.sql; DOWN10=rollback/20261116000010_contracts.down.sql; DOWN9=rollback/20261116000009_service_catalog.down.sql; DOWN8=rollback/20261116000008_roles_permissions.down.sql

echo "== 1/4 base (0001–0005, single-tenant)";      newdb orbia_base;     mig "${BASE[@]}"; run tests/rules.base.test.sql
echo "== 2/4 multi-tenant (0001–0006)";             newdb orbia_tenant;   mig "${BASE[@]}" "$UP" "$UP7" "$UP8" "$UP9" "$UP10"; run tests/rules.test.sql; run tests/tenant.test.sql; run tests/ratelimit.test.sql; run tests/roles.test.sql; run tests/catalog.test.sql; run tests/contracts.test.sql
echo "== 3/4 dados legados (migrar e reverter)";    newdb orbia_legacy;   mig "${BASE[@]}"; psql -q -v ON_ERROR_STOP=1 < tests/legacy_seed.sql
                                                   mig "$UP"; run tests/legacy.test.sql; mig "$UP7" "$UP8"; run tests/legacy8.test.sql; mig "$UP9"; run tests/legacy9.test.sql; mig "$UP10"; run tests/legacy10.test.sql; mig "$DOWN10" "$DOWN9" "$DOWN8" "$DOWN7" "$DOWN"; run tests/legacy_down.test.sql
echo "== 4/4 rollback em banco vazio";              newdb orbia_rollback; mig "${BASE[@]}" "$UP" "$UP7" "$UP8" "$UP9" "$UP10" "$DOWN10" "$DOWN9" "$DOWN8" "$DOWN7" "$DOWN"; run tests/rules.base.test.sql
echo "OK — todos os testes SQL passaram"
