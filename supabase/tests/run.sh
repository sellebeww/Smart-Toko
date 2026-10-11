#!/usr/bin/env bash
# Menjalankan supabase/setup.sql di Postgres sungguhan (Docker) lalu menguji
# kebijakan keamanannya. Butuh Docker yang berjalan.
#
#   supabase/tests/run.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
name="smarttoko-sql-test-$$"
image="${POSTGRES_IMAGE:-postgres:16-alpine}"

cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$name" -e POSTGRES_PASSWORD=test \
  -v "$root:/work:ro" "$image" >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
# pg_isready bisa lolos sebelum server awal selesai di-restart oleh image.
sleep 2

psql() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

echo "== shim"
psql -f /work/tests/00_shim.sql
echo "== setup.sql (pertama)"
psql -f /work/setup.sql
echo "== setup.sql (kedua: harus aman dijalankan ulang)"
psql -f /work/setup.sql
echo "== uji kebijakan"
psql -f /work/tests/10_policies.sql
echo "== uji sinkronisasi dan karyawan"
psql -f /work/tests/20_sync_team.sql
