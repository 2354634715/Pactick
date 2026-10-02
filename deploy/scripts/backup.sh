#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'backup error: %s\n' "$*" >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="${PACTICK_APP_DIR:-$(cd -- "$script_dir/../.." && pwd)}"
initial_config_dir="${PACTICK_CONFIG_DIR:-/opt/pactick/config}"
compose_env="${PACTICK_COMPOSE_ENV:-$initial_config_dir/compose.env}"
[[ -r "$compose_env" ]] || fail "cannot read $compose_env"

set -a
# shellcheck disable=SC1090
source "$compose_env"
config_dir="${PACTICK_CONFIG_DIR:-$initial_config_dir}"
backup_env="$config_dir/backup.env"
if [[ -r "$backup_env" ]]; then
    # shellcheck disable=SC1090
    source "$backup_env"
fi
set +a

mode="${1:-daily}"
case "$mode" in
    daily|pre-deploy) ;;
    *) fail "mode must be daily or pre-deploy" ;;
esac

backup_root="${PACTICK_BACKUP_ROOT:-/var/backups/pactick}"
[[ "$backup_root" == /* && "$backup_root" != "/" && ${#backup_root} -ge 10 ]] || \
    fail "PACTICK_BACKUP_ROOT must be a specific absolute directory"

daily_dir="$backup_root/daily"
weekly_dir="$backup_root/weekly"
monthly_dir="$backup_root/monthly"
predeploy_dir="$backup_root/pre-deploy"
mkdir -p -- "$daily_dir" "$weekly_dir" "$monthly_dir" "$predeploy_dir"
chmod 0700 "$backup_root" "$daily_dir" "$weekly_dir" "$monthly_dir" "$predeploy_dir"
[[ ! -L "$backup_root/.backup.lock" ]] || fail "backup lock must not be a symlink"
command -v flock >/dev/null 2>&1 || fail "flock is required (install util-linux)"
exec 8>"$backup_root/.backup.lock"
flock -n 8 || fail "another backup is already running"

case "$mode" in
    daily) target_dir="$daily_dir" ;;
    pre-deploy) target_dir="$predeploy_dir" ;;
esac

compose=(docker compose --project-directory "$app_dir" --env-file "$compose_env" -f "$app_dir/compose.production.yaml")
timestamp="$(date -u +%Y%m%d-%H%M%S)"
temporary_path="$(mktemp "$target_dir/.pactick-$timestamp.dump.tmp.XXXXXX")"
final_path="$target_dir/pactick-$timestamp-${temporary_path##*.}.dump"
trap 'rm -f -- "$temporary_path"' EXIT

"${compose[@]}" exec -T postgres sh -eu -c \
    'exec pg_dump --format=custom --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
    > "$temporary_path"
[[ -s "$temporary_path" ]] || fail "pg_dump produced an empty file"
"${compose[@]}" exec -T postgres pg_restore --list < "$temporary_path" >/dev/null

chmod 0600 "$temporary_path"
mv -- "$temporary_path" "$final_path"
trap - EXIT

write_checksum() {
    local dump_path="$1"
    local dump_dir dump_name
    dump_dir="$(dirname -- "$dump_path")"
    dump_name="$(basename -- "$dump_path")"
    (cd -- "$dump_dir" && sha256sum "$dump_name" > "$dump_name.sha256")
    chmod 0600 "$dump_path" "$dump_path.sha256"
}

prune_to_count() {
    local directory="$1"
    local keep="$2"
    local -a dumps=()
    mapfile -t dumps < <(
        find "$directory" -maxdepth 1 -type f -name 'pactick-*.dump' -printf '%T@:%p\n' \
            | sort -rn \
            | cut -d: -f2-
    )
    local index
    for ((index=keep; index<${#dumps[@]}; index++)); do
        [[ "${dumps[$index]}" == "$directory"/pactick-*.dump ]] || fail "refusing to prune an unexpected path"
        rm -f -- "${dumps[$index]}" "${dumps[$index]}.sha256"
    done
}

write_checksum "$final_path"

if [[ "$mode" == "daily" ]]; then
    if [[ "$(date -u +%u)" == "7" ]]; then
        weekly_path="$weekly_dir/$(basename -- "$final_path")"
        cp -- "$final_path" "$weekly_path"
        write_checksum "$weekly_path"
    fi
    if [[ "$(date -u +%d)" == "01" ]]; then
        monthly_path="$monthly_dir/$(basename -- "$final_path")"
        cp -- "$final_path" "$monthly_path"
        write_checksum "$monthly_path"
    fi
fi

prune_to_count "$daily_dir" 7
prune_to_count "$weekly_dir" 4
prune_to_count "$monthly_dir" 6
prune_to_count "$predeploy_dir" 10

printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$final_path" > "$backup_root/last-success.utc"
chmod 0600 "$backup_root/last-success.utc"
printf 'backup completed locally: %s\n' "$final_path"
printf 'warning: pre-1.0 backups exist only on this server; host or disk loss is not covered\n' >&2
