#!/usr/bin/env bash
# Test release sequencing and backup failure with fake Docker/curl; no daemon.
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/pactick-release.XXXXXX")"
test_root="$(realpath "$test_root")"
temp_root="$(realpath "${TMPDIR:-/tmp}")"
cleanup() {
    [[ "$test_root" == "$temp_root"/pactick-release.* && "$test_root" != "$temp_root" ]] || return 1
    rm -rf -- "$test_root"
}
trap cleanup EXIT
mkdir "$test_root/bin"
bash "$script_dir/../scripts/install.sh" install --prepare-only --local-only \
    --config-dir "$test_root/config" --backup-dir "$test_root/backups" >/dev/null
cat > "$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    *'compose version'*|*'config --quiet'*) exit 0 ;;
    *'build --pull'*) echo BUILD >> "$EVENTS" ;;
    *'up -d postgres'*) echo DATABASE >> "$EVENTS" ;;
    *pg_isready*) exit 0 ;;
    *pg_dump*)
        echo BACKUP >> "$EVENTS"
        [[ "${FAIL_BACKUP:-false}" != true ]] || exit 1
        printf 'mock-database-dump\n'
        ;;
    *'pg_restore --list'*) cat >/dev/null; echo CHECK_BACKUP >> "$EVENTS" ;;
    *' stop api') echo STOP_API >> "$EVENTS" ;;
    *'run --rm --no-deps migrate'*) echo MIGRATE >> "$EVENTS" ;;
    *'--force-recreate --wait --wait-timeout 90 api'*) echo API >> "$EVENTS" ;;
    *' ps') exit 0 ;;
    *) printf 'Unexpected Docker call: %s\n' "$*" >&2; exit 1 ;;
esac
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/curl"
# Windows MSYS permissions do not model chmod; Linux exercises real stat.
if [[ "$(uname -s)" != Linux ]]; then
    printf '#!/usr/bin/env bash\nprintf "600\\n"\n' > "$test_root/bin/stat"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/flock"
fi
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH" EVENTS="$test_root/events"
export PACTICK_CONFIG_DIR="$test_root/config"
bash "$script_dir/../scripts/release.sh" > "$test_root/output" 2>&1
[[ "$(cat "$EVENTS")" == $'BUILD\nDATABASE\nBACKUP\nCHECK_BACKUP\nSTOP_API\nMIGRATE\nAPI' ]]
[[ -s "$test_root/backups/last-success.utc" ]]
: > "$EVENTS"
if FAIL_BACKUP=true bash "$script_dir/../scripts/release.sh" > "$test_root/output" 2>&1; then
    printf 'Release continued after failed backup.\n' >&2
    exit 1
fi
[[ "$(cat "$EVENTS")" == $'BUILD\nDATABASE\nBACKUP' ]]
printf 'Release ordering and failed-backup tests passed (mock Docker).\n'
