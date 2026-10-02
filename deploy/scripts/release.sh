#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

fail() {
    printf 'release error: %s\n' "$*" >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="${PACTICK_APP_DIR:-$(cd -- "$script_dir/../.." && pwd)}"
initial_config_dir="${PACTICK_CONFIG_DIR:-/opt/pactick/config}"
compose_env="${PACTICK_COMPOSE_ENV:-$initial_config_dir/compose.env}"
release_target="${PACTICK_RELEASE_CONFIG_TARGET:-}"

PACTICK_APP_DIR="$app_dir" PACTICK_COMPOSE_ENV="$compose_env" bash "$script_dir/validate-config.sh"

set -a
# shellcheck disable=SC1090
source "$compose_env"
set +a

config_dir="${PACTICK_CONFIG_DIR:-$initial_config_dir}"
pending_path="$config_dir/.release-pending"
[[ ! -L "$pending_path" && ( ! -e "$pending_path" || -f "$pending_path" ) ]] ||
    fail "release state must be a regular file: $pending_path"
if [[ -n "$release_target" ]]; then
    [[ "$release_target" == "$config_dir/compose.env" && "$compose_env" != "$release_target" ]] ||
        fail "candidate configuration must target $config_dir/compose.env"
    [[ -f "$release_target" && ! -L "$release_target" ]] || fail "release target must be a regular file"
fi
state_temporary=
cleanup() { [[ -z "$state_temporary" ]] || rm -f -- "$state_temporary"; }
trap cleanup EXIT
trap 'if [[ -e "$pending_path" ]]; then printf "Release incomplete after migration started. Registration changes are blocked; see docs/SELF_HOSTING.md. No database rollback was attempted.\n" >&2; fi' ERR
record_pending() {
    state_temporary="$(mktemp "$config_dir/.release-state.XXXXXX")"
    printf 'image=%s\nphase=%s\n' "$PACTICK_IMAGE" "$1" > "$state_temporary"
    chmod 0600 "$state_temporary"
    mv -- "$state_temporary" "$pending_path"
    state_temporary=
}

compose=(docker compose --project-directory "$app_dir" --env-file "$compose_env" -f "$app_dir/compose.production.yaml")

"${compose[@]}" build --pull api migrate
"${compose[@]}" up -d postgres

database_ready=false
for _ in {1..30}; do
    if "${compose[@]}" exec -T postgres sh -eu -c \
        'pg_isready --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' >/dev/null 2>&1; then
        database_ready=true
        break
    fi
    sleep 2
done
[[ "$database_ready" == "true" ]] || fail "PostgreSQL did not become ready within 60 seconds"

PACTICK_APP_DIR="$app_dir" PACTICK_COMPOSE_ENV="$compose_env" bash "$script_dir/backup.sh" pre-deploy
# Older API releases do not honor the migration barrier. Stop their writes
# after backup succeeds and before invoking any database migration.
"${compose[@]}" stop api
# A failed migration command can still leave earlier migrations committed.
# Keep this marker until API readiness and configuration commit both succeed.
record_pending migration-started
"${compose[@]}" --profile maintenance run --rm --no-deps migrate
record_pending api-starting
"${compose[@]}" up -d --no-deps --force-recreate --wait --wait-timeout 90 api

http_port="${PACTICK_HTTP_PORT:-8080}"
api_ready=false
for _ in {1..30}; do
    if curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:$http_port/readyz" >/dev/null 2>&1; then
        api_ready=true
        break
    fi
    sleep 2
done
if [[ "$api_ready" != "true" ]]; then
    "${compose[@]}" logs --tail=100 api >&2 || true
    fail "API did not become ready within 60 seconds; no automatic database rollback was attempted"
fi

"${compose[@]}" ps
if [[ -n "$release_target" ]]; then
    chmod 0600 "$compose_env"
    mv -- "$compose_env" "$release_target"
fi
rm -f -- "$pending_path"
printf 'release is ready on 127.0.0.1:%s using image %s\n' "$http_port" "$PACTICK_IMAGE"
