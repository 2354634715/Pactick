#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'restore check error: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail "usage: restore-check.sh /absolute/path/to/backup.dump"
dump_path="$(realpath -- "$1")"
[[ -f "$dump_path" && -s "$dump_path" ]] || fail "backup file is missing or empty"

if [[ -f "$dump_path.sha256" ]]; then
    dump_dir="$(dirname -- "$dump_path")"
    dump_name="$(basename -- "$dump_path")"
    (cd -- "$dump_dir" && sha256sum --check "$dump_name.sha256")
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
initial_config_dir="${PACTICK_CONFIG_DIR:-/opt/pactick/config}"
compose_env="${PACTICK_COMPOSE_ENV:-$initial_config_dir/compose.env}"
if [[ -r "$compose_env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$compose_env"
    set +a
fi

postgres_image="${POSTGRES_IMAGE:-postgres:17-alpine}"
suffix="$(date -u +%Y%m%d%H%M%S)-$RANDOM"
container_name="pactick-restore-$suffix"
volume_name="pactick-restore-$suffix"
keep_restore="${PACTICK_KEEP_RESTORE:-false}"
[[ "$container_name" == pactick-restore-* && "$volume_name" == pactick-restore-* ]] || \
    fail "generated restore resource names are invalid"
if docker container inspect "$container_name" >/dev/null 2>&1 || docker volume inspect "$volume_name" >/dev/null 2>&1; then
    fail "generated restore resource name unexpectedly already exists"
fi

container_created=false
volume_created=false

cleanup() {
    if [[ "$keep_restore" != "true" ]]; then
        if [[ "$container_created" == "true" ]]; then
            docker rm --force "$container_name" >/dev/null 2>&1 || true
        fi
        if [[ "$volume_created" == "true" ]]; then
            docker volume rm "$volume_name" >/dev/null 2>&1 || true
        fi
    fi
}
trap cleanup EXIT

docker volume create "$volume_name" >/dev/null
volume_created=true
docker run --detach \
    --name "$container_name" \
    --network none \
    --env POSTGRES_DB=pactick_restore \
    --env POSTGRES_USER=pactick_restore \
    --env POSTGRES_PASSWORD=restore-check-only \
    --volume "$volume_name:/var/lib/postgresql/data" \
    "$postgres_image" >/dev/null
container_created=true

database_ready=false
for _ in {1..30}; do
    if docker exec "$container_name" pg_isready \
        --username=pactick_restore --dbname=pactick_restore >/dev/null 2>&1; then
        database_ready=true
        break
    fi
    sleep 2
done
[[ "$database_ready" == "true" ]] || fail "isolated PostgreSQL did not become ready"

docker exec -i "$container_name" pg_restore \
    --exit-on-error \
    --no-owner \
    --no-privileges \
    --username=pactick_restore \
    --dbname=pactick_restore < "$dump_path"

ledger_exists="$(docker exec "$container_name" psql --tuples-only --no-align \
    --username=pactick_restore --dbname=pactick_restore \
    --command="SELECT to_regclass('public.schema_migrations') IS NOT NULL")"
users_exists="$(docker exec "$container_name" psql --tuples-only --no-align \
    --username=pactick_restore --dbname=pactick_restore \
    --command="SELECT to_regclass('public.users') IS NOT NULL")"
[[ "$ledger_exists" == "t" && "$users_exists" == "t" ]] || fail "restored database is missing required tables"

migration_count="$(docker exec "$container_name" psql --tuples-only --no-align \
    --username=pactick_restore --dbname=pactick_restore \
    --command='SELECT count(*) FROM schema_migrations')"
printf 'restore check passed: %s migration(s) restored\n' "$migration_count"
if [[ "$keep_restore" == "true" ]]; then
    printf 'isolated resources retained: container=%s volume=%s\n' "$container_name" "$volume_name"
fi
