#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'verification error: %s\n' "$*" >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="${PACTICK_APP_DIR:-$(cd -- "$script_dir/../.." && pwd)}"
initial_config_dir="${PACTICK_CONFIG_DIR:-/opt/pactick/config}"
compose_env="${PACTICK_COMPOSE_ENV:-$initial_config_dir/compose.env}"

PACTICK_APP_DIR="$app_dir" PACTICK_COMPOSE_ENV="$compose_env" bash "$script_dir/validate-config.sh"

set -a
# shellcheck disable=SC1090
source "$compose_env"
config_dir="${PACTICK_CONFIG_DIR:-$initial_config_dir}"
if [[ -r "$config_dir/backup.env" ]]; then
    # shellcheck disable=SC1090
    source "$config_dir/backup.env"
fi
set +a

compose=(docker compose --project-directory "$app_dir" --env-file "$compose_env" -f "$app_dir/compose.production.yaml")
api_id="$("${compose[@]}" ps -q api)"
postgres_id="$("${compose[@]}" ps -q postgres)"
[[ -n "$api_id" && -n "$postgres_id" ]] || fail "API and PostgreSQL containers must exist"
[[ "$(docker inspect -f '{{.State.Running}}' "$api_id")" == "true" ]] || fail "API container is not running"
[[ "$(docker inspect -f '{{.State.Running}}' "$postgres_id")" == "true" ]] || fail "PostgreSQL container is not running"
[[ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$api_id")" == "healthy" ]] || \
    fail "API container health check is not healthy"
[[ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$postgres_id")" == "healthy" ]] || \
    fail "PostgreSQL container health check is not healthy"

postgres_bindings="$(docker inspect -f '{{json .HostConfig.PortBindings}}' "$postgres_id")"
[[ "$postgres_bindings" == "{}" || "$postgres_bindings" == "null" ]] || \
    fail "PostgreSQL unexpectedly has host port bindings: $postgres_bindings"

http_port="${PACTICK_HTTP_PORT:-8080}"
api_binding="$("${compose[@]}" port api 8080)"
[[ "$api_binding" == "127.0.0.1:$http_port" ]] || fail "API binding is $api_binding, expected 127.0.0.1:$http_port"
curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:$http_port/healthz" >/dev/null
curl --fail --silent --show-error --max-time 5 "http://127.0.0.1:$http_port/readyz" >/dev/null

backup_root="${PACTICK_BACKUP_ROOT:-/var/backups/pactick}"
marker="$backup_root/last-success.utc"
[[ -s "$marker" ]] || fail "backup success marker is missing: $marker"
last_backup="$(awk 'NR == 1 {print $1}' "$marker")"
last_backup_epoch="$(date -u -d "$last_backup" +%s)" || fail "backup marker timestamp is invalid"
now_epoch="$(date -u +%s)"
(( now_epoch - last_backup_epoch <= 93600 )) || fail "the most recent successful backup is older than 26 hours"

if [[ -n "${PACTICK_PUBLIC_URL:-}" ]]; then
    [[ "$PACTICK_PUBLIC_URL" == https://* ]] || fail "PACTICK_PUBLIC_URL must use HTTPS"
    public_url="${PACTICK_PUBLIC_URL%/}"
    curl --proto '=https' --fail --silent --show-error --max-time 10 "$public_url/readyz" >/dev/null
    http_url="http://${public_url#https://}"
    redirect_status="$(curl --silent --output /dev/null --max-time 10 --write-out '%{http_code}' "$http_url/healthz")"
    [[ "$redirect_status" == "301" || "$redirect_status" == "308" ]] || \
        fail "HTTP endpoint returned $redirect_status instead of a permanent HTTPS redirect"
fi

printf 'deployment verification passed under the pre-1.0 local-backup policy\n'
printf 'warning: host or disk loss remains unrecoverable until 1.0 offsite disaster recovery is implemented\n' >&2
