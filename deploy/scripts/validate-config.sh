#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'configuration error: %s\n' "$*" >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="${PACTICK_APP_DIR:-$(cd -- "$script_dir/../.." && pwd)}"
initial_config_dir="${PACTICK_CONFIG_DIR:-/opt/pactick/config}"
compose_env="${PACTICK_COMPOSE_ENV:-$initial_config_dir/compose.env}"

[[ -r "$compose_env" ]] || fail "cannot read $compose_env"
# Validate permissions before sourcing any administrator configuration.
for env_file in "$compose_env" "$initial_config_dir/api.env" "$initial_config_dir/postgres.env" "$initial_config_dir/backup.env"; do
    [[ -e "$env_file" ]] || continue
    [[ -f "$env_file" && ! -L "$env_file" ]] || fail "$env_file must be a regular file"
    mode="$(stat -c '%a' "$env_file")"
    if (( (8#$mode & 077) != 0 )); then
        fail "$env_file must not be readable or writable by group/other (use chmod 0600)"
    fi
done
set -a
# shellcheck disable=SC1090
source "$compose_env"
set +a

config_dir="${PACTICK_CONFIG_DIR:-$initial_config_dir}"
api_env="$config_dir/api.env"
postgres_env="$config_dir/postgres.env"
for env_file in "$api_env" "$postgres_env"; do
    [[ -r "$env_file" ]] || fail "cannot read $env_file"
    if grep -Eq 'REPLACE_ME|<[^>]+>' "$env_file"; then
        fail "$env_file still contains a placeholder"
    fi
    mode="$(stat -c '%a' "$env_file")"
    if (( (8#$mode & 077) != 0 )); then
        fail "$env_file must not be readable or writable by group/other (use chmod 0600)"
    fi
done

set -a
# shellcheck disable=SC1090
source "$api_env"
# shellcheck disable=SC1090
source "$postgres_env"
set +a

[[ "${APP_ENV:-}" == "production" ]] || fail "APP_ENV must be production"
[[ "${HTTP_ADDRESS:-}" == ":8080" ]] || fail "HTTP_ADDRESS must be :8080 inside the container"
[[ "${AUTO_MIGRATE:-}" == "false" ]] || fail "AUTO_MIGRATE must be false for explicit production migrations"
[[ "${REGISTRATION_ENABLED:-}" == "true" || "${REGISTRATION_ENABLED:-}" == "false" ]] || \
    fail "REGISTRATION_ENABLED must be true or false"
jwt_secret="${AUTH_JWT_SECRET:-}"
[[ ${#jwt_secret} -ge 64 ]] || fail "AUTH_JWT_SECRET must contain at least 64 characters"
[[ "${POSTGRES_USER:-}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || fail "POSTGRES_USER contains unsupported characters"
[[ "${POSTGRES_DB:-}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || fail "POSTGRES_DB contains unsupported characters"
[[ "${POSTGRES_PASSWORD:-}" =~ ^[[:xdigit:]]{64,}$ ]] || \
    fail "POSTGRES_PASSWORD must be at least 32 random bytes encoded as hexadecimal"

expected_database_url="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}?sslmode=disable"
[[ "${DATABASE_URL:-}" == "$expected_database_url" ]] || \
    fail "DATABASE_URL must use the same PostgreSQL user, database and hexadecimal password as postgres.env"

if [[ -n "${ALLOWED_ORIGINS:-}" ]]; then
    IFS=',' read -ra origins <<< "$ALLOWED_ORIGINS"
    for origin in "${origins[@]}"; do
        origin="${origin#"${origin%%[![:space:]]*}"}"
        origin="${origin%"${origin##*[![:space:]]}"}"
        [[ "$origin" == https://* && "$origin" != */ ]] || \
            fail "each ALLOWED_ORIGINS entry must be an exact HTTPS origin without a trailing slash"
    done
fi

[[ -n "${PACTICK_IMAGE:-}" ]] || fail "PACTICK_IMAGE is required"
image_name="${PACTICK_IMAGE##*/}"
[[ "$image_name" == *:* || "$PACTICK_IMAGE" == *@sha256:* ]] || \
    fail "PACTICK_IMAGE must include an explicit tag or digest"
[[ "$PACTICK_IMAGE" != *:latest ]] || fail "PACTICK_IMAGE must not use latest"

command -v docker >/dev/null 2>&1 || fail "docker is not installed"
docker compose version >/dev/null 2>&1 || fail "the Docker Compose plugin is not installed"
docker compose \
    --project-directory "$app_dir" \
    --env-file "$compose_env" \
    -f "$app_dir/compose.production.yaml" \
    config --quiet

printf 'production configuration is valid\n'
