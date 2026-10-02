#!/usr/bin/env bash
# Run the real upgrade and registration paths with isolated config and fake
# Docker/curl. No containers, root privileges or host service writes are used.
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "$script_dir/../.." && pwd)"
stage="${1:?failure stage or success is required}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/pactick-upgrade.XXXXXX")"
test_root="$(realpath "$test_root")"
temp_root="$(realpath "${TMPDIR:-/tmp}")"
cleanup() {
    [[ "$test_root" == "$temp_root"/pactick-upgrade.* && "$test_root" != "$temp_root" ]] || return 1
    rm -rf -- "$test_root"
}
trap cleanup EXIT
trap 'printf "Upgrade case failed: %s\n" "$stage" >&2; cat "$test_root/output" >&2' ERR
[[ ! "$test_root" =~ [[:space:]] ]] || { printf 'Use a TMPDIR without whitespace.\n' >&2; exit 1; }
mkdir -p "$test_root/app/deploy/scripts" "$test_root/bin"
cp -- "$app_dir/compose.production.yaml" "$test_root/app/compose.production.yaml"
cp -- "$app_dir/deploy/scripts/"*.sh "$test_root/app/deploy/scripts/"

# Keep all operational code. Remove only platform/privilege preconditions so
# the fixture can run as an ordinary user on Linux and on Windows Git Bash.
sed -e '/^    \[\[ "$(uname -s)" == Linux \]\] || fail /d' \
    -e '/^    (( EUID == 0 )) || fail /d' \
    "$app_dir/deploy/scripts/install.sh" > "$test_root/app/deploy/scripts/install.sh"
installer="$test_root/app/deploy/scripts/install.sh"
unset PACTICK_IMAGE PACTICK_CONFIG_DIR PACTICK_COMPOSE_ENV PACTICK_RELEASE_CONFIG_TARGET
bash "$installer" install --prepare-only --local-only \
    --config-dir "$test_root/config" --backup-dir "$test_root/backups" > "$test_root/output" 2>&1
cp -- "$test_root/config/compose.env" "$test_root/original-compose.env"
cp -- "$test_root/config/api.env" "$test_root/original-api.env"
original_image="$(sed -n 's/^PACTICK_IMAGE=//p' "$test_root/config/compose.env")"
printf '%s\n' "$original_image" > "$test_root/running-image"

cat > "$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
env_file=
previous=
for argument in "$@"; do
    if [[ "$previous" == --env-file ]]; then env_file="$argument"; fi
    previous="$argument"
done
image=
[[ -z "$env_file" ]] || image="$(sed -n 's/^PACTICK_IMAGE=//p' "$env_file")"
event() {
    # Candidate operations must not rewrite formal config before readiness.
    if [[ "$env_file" != "$TEST_ROOT/config/compose.env" ]]; then
        cmp -- "$TEST_ROOT/original-compose.env" "$TEST_ROOT/config/compose.env"
    fi
    printf '%s %s\n' "$1" "$image" >> "$EVENTS"
}
case "$*" in
    *'compose version'*|'info'|*'config --quiet'*) exit 0 ;;
    *'build --pull'*) event BUILD; [[ "$FAIL_STAGE" != build ]] ;;
    *'up -d postgres'*) event DATABASE ;;
    *pg_isready*) [[ "$FAIL_STAGE" != postgres ]] ;;
    *pg_dump*)
        event BACKUP
        [[ "$FAIL_STAGE" != backup ]] || exit 53
        printf 'mock-database-dump\n'
        ;;
    *'pg_restore --list'*) cat >/dev/null; event CHECK_BACKUP ;;
    *' stop api')
        event STOP_API
        [[ "$FAIL_STAGE" != stop ]] || exit 54
        : > "$TEST_ROOT/running-image"
        ;;
    *'run --rm --no-deps migrate'*)
        event MIGRATE
        # Migration must not overlap the old API, which has no barrier lock.
        [[ ! -s "$TEST_ROOT/running-image" ]]
        # A migration command may commit some work and then report failure.
        printf 'migrated\n' > "$TEST_ROOT/database-state"
        [[ "$FAIL_STAGE" != migrate ]]
        ;;
    *'--force-recreate --wait --wait-timeout 90 api'*)
        event API
        printf '%s\n' "$image" > "$TEST_ROOT/running-image"
        [[ "$FAIL_STAGE" != api ]]
        ;;
    *' ps -q api') printf 'mock-api\n' ;;
    *' ps -q postgres') printf 'mock-postgres\n' ;;
    *' port api 8080') printf '127.0.0.1:8080\n' ;;
    'inspect -f {{.State.Running}} '*) printf 'true\n' ;;
    'inspect -f {{if .State.Health}}{{.State.Health.Status}}{{end}} '*) printf 'healthy\n' ;;
    'inspect -f {{json .HostConfig.PortBindings}} '*) printf '{}\n' ;;
    *'logs --tail=100 api') exit 0 ;;
    *' ps') event PS ;;
    *) printf 'Unexpected Docker call: %s\n' "$*" >&2; exit 99 ;;
esac
MOCK
cat > "$test_root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
[[ "$FAIL_STAGE" != readyz || "$*" != */readyz ]]
MOCK
export REAL_MKTEMP="$(command -v mktemp)"
cat > "$test_root/bin/mktemp" <<'MOCK'
#!/usr/bin/env bash
if [[ "$FAIL_STAGE" == state && "$*" == *'/.release-state.'* ]]; then exit 55; fi
exec "$REAL_MKTEMP" "$@"
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/sleep"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/flock"
if [[ "$(uname -s)" != Linux ]]; then
    # MSYS chmod/stat do not model Linux file permission bits.
    printf '#!/usr/bin/env bash\nprintf "600\\n"\n' > "$test_root/bin/stat"
fi
chmod +x "$test_root/bin/"*
export PATH="$test_root/bin:$PATH" EVENTS="$test_root/events" TEST_ROOT="$test_root"
export FAIL_STAGE="$stage"
: > "$EVENTS"

run_upgrade() {
    bash "$installer" upgrade --config-dir "$test_root/config" > "$test_root/output" 2>&1
}
assert_no_candidate_file() {
    [[ -z "$(find "$test_root/config" -maxdepth 1 \( -name '.release-compose.*' -o -name '.release-state.*' \) -print)" ]]
}
if [[ "$stage" == success ]]; then
    run_upgrade
    new_image="$(sed -n 's/^PACTICK_IMAGE=//p' "$test_root/config/compose.env")"
    [[ "$new_image" != "$original_image" ]]
    [[ "$(cat "$test_root/running-image")" == "$new_image" ]]
    [[ ! -e "$test_root/config/.release-pending" ]]
    [[ "$(awk '{print $1}' "$EVENTS")" == $'BUILD\nDATABASE\nBACKUP\nCHECK_BACKUP\nSTOP_API\nMIGRATE\nAPI\nPS' ]]
    assert_no_candidate_file
    FAIL_STAGE=none bash "$installer" registration open --config-dir "$test_root/config" > "$test_root/output" 2>&1
    [[ "$(tail -n 1 "$EVENTS")" == "API $new_image" ]]
else
    [[ "$stage" != retry ]] || export FAIL_STAGE=migrate
    if run_upgrade; then printf 'Upgrade unexpectedly succeeded: %s\n' "$stage" >&2; exit 1; fi
    cmp -- "$test_root/original-compose.env" "$test_root/config/compose.env"
    assert_no_candidate_file
    candidate_image="$(awk '$1 == "BUILD" {print $2; exit}' "$EVENTS")"
    [[ -n "$candidate_image" && "$candidate_image" != "$original_image" ]]
    case "$stage" in
        build) expected_events=BUILD ;;
        postgres) expected_events=$'BUILD\nDATABASE' ;;
        backup) expected_events=$'BUILD\nDATABASE\nBACKUP' ;;
        stop|state) expected_events=$'BUILD\nDATABASE\nBACKUP\nCHECK_BACKUP\nSTOP_API' ;;
        migrate|retry) expected_events=$'BUILD\nDATABASE\nBACKUP\nCHECK_BACKUP\nSTOP_API\nMIGRATE' ;;
        api|readyz) expected_events=$'BUILD\nDATABASE\nBACKUP\nCHECK_BACKUP\nSTOP_API\nMIGRATE\nAPI' ;;
        *) printf 'Unknown test stage: %s\n' "$stage" >&2; exit 1 ;;
    esac
    [[ "$(awk '{print $1}' "$EVENTS")" == "$expected_events" ]]
    case "$stage" in
        build|postgres|backup|stop|state)
            [[ ! -e "$test_root/config/.release-pending" && ! -e "$test_root/database-state" ]]
            if [[ "$stage" == state ]]; then
                [[ ! -s "$test_root/running-image" ]]
            else
                [[ "$(cat "$test_root/running-image")" == "$original_image" ]]
            fi
            ! grep -q '^MIGRATE ' "$EVENTS"
            FAIL_STAGE=none bash "$installer" registration open --config-dir "$test_root/config" > "$test_root/output" 2>&1
            [[ "$(tail -n 1 "$EVENTS")" == "API $original_image" ]]
            [[ "$(cat "$test_root/running-image")" == "$original_image" ]]
            ;;
        migrate|api|readyz|retry)
            [[ -s "$test_root/config/.release-pending" && "$(cat "$test_root/database-state")" == migrated ]]
            grep -Fqx "image=$candidate_image" "$test_root/config/.release-pending"
            before_events="$(cat "$EVENTS")"
            if FAIL_STAGE=none bash "$installer" registration open --config-dir "$test_root/config" > "$test_root/output" 2>&1; then
                printf 'Registration proceeded after an incomplete migration/release.\n' >&2; exit 1
            fi
            grep -Fq 'release started database migration but did not finish' "$test_root/output"
            cmp -- "$test_root/original-api.env" "$test_root/config/api.env"
            [[ "$before_events" == "$(cat "$EVENTS")" ]]
            if [[ "$stage" == migrate || "$stage" == retry ]]; then
                ! grep -q '^API ' "$EVENTS"
                [[ ! -s "$test_root/running-image" ]]
            fi
            if [[ "$stage" == retry ]]; then
                cp -- "$test_root/config/.release-pending" "$test_root/original-pending"
                export FAIL_STAGE=build
                if run_upgrade; then printf 'Failed retry unexpectedly succeeded.\n' >&2; exit 1; fi
                cmp -- "$test_root/original-pending" "$test_root/config/.release-pending"
                cmp -- "$test_root/original-compose.env" "$test_root/config/compose.env"
                export FAIL_STAGE=none
                run_upgrade
                [[ ! -e "$test_root/config/.release-pending" ]]
                recovered_image="$(sed -n 's/^PACTICK_IMAGE=//p' "$test_root/config/compose.env")"
                [[ "$recovered_image" != "$original_image" && "$recovered_image" != "$candidate_image" ]]
                [[ "$(cat "$test_root/running-image")" == "$recovered_image" ]]
                bash "$installer" registration open --config-dir "$test_root/config" > "$test_root/output" 2>&1
                [[ "$(tail -n 1 "$EVENTS")" == "API $recovered_image" ]]
                assert_no_candidate_file
            fi
            ;;
        *) printf 'Unknown test stage: %s\n' "$stage" >&2; exit 1 ;;
    esac
fi
printf 'Upgrade configuration case passed: %s (mock Docker).\n' "$stage"
