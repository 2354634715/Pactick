#!/usr/bin/env bash
# Exercises configuration creation and failure paths without Docker or root.
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
installer="$script_dir/../scripts/install.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/pactick-install.XXXXXX")"
cleanup() {
    # Remove only files created by this test, within its verified temp directory.
    [[ "$test_root" == */pactick-install.* ]] || return 1
    for directory in complete partial domain; do
        for file in api.env postgres.env compose.env backup.env; do
            rm -f -- "$test_root/$directory/$file"
        done
        rmdir -- "$test_root/$directory" 2>/dev/null || true
    done
    rm -f -- "$test_root/output"
    rmdir -- "$test_root" 2>/dev/null || true
}
trap cleanup EXIT
expect_failure() {
    if bash "$installer" "$@" > "$test_root/output" 2>&1; then
        printf 'Expected failure for: %s\n' "$*" >&2
        exit 1
    fi
}
bash "$installer" install --prepare-only --local-only --config-dir "$test_root/complete" --port 8093 > "$test_root/output"
before="$(sha256sum "$test_root/complete/"*.env)"
set -a
# shellcheck disable=SC1091
source "$test_root/complete/api.env"
# shellcheck disable=SC1091
source "$test_root/complete/postgres.env"
set +a
[[ "$POSTGRES_PASSWORD" =~ ^[[:xdigit:]]{64}$ ]]
[[ "$AUTH_JWT_SECRET" =~ ^[[:xdigit:]]{128}$ ]]
[[ "$DATABASE_URL" == "postgres://pactick:$POSTGRES_PASSWORD@postgres:5432/pactick?sslmode=disable" ]]
[[ "$AUTO_MIGRATE" == false && "$REGISTRATION_ENABLED" == false ]]
! grep -Fq "$POSTGRES_PASSWORD" "$test_root/output"
! grep -Fq "$AUTH_JWT_SECRET" "$test_root/output"
grep -Fq 'PACTICK_HTTP_PORT=8093' "$test_root/complete/compose.env"
# Retry must preserve all secrets/settings, even if different port is supplied.
bash "$installer" install --prepare-only --local-only --config-dir "$test_root/complete" --port 8094 > "$test_root/output"
[[ "$before" == "$(sha256sum "$test_root/complete/"*.env)" ]]
mkdir "$test_root/partial"
cp "$test_root/complete/api.env" "$test_root/partial/api.env"
expect_failure install --prepare-only --local-only --config-dir "$test_root/partial"
[[ ! -e "$test_root/partial/postgres.env" ]]
expect_failure install --prepare-only --config-dir "$test_root/domain" --domain 'bad;hostname' --email admin@example.com --accept-acme-terms
expect_failure install --prepare-only --config-dir "$test_root/domain" --domain api.example.com --email admin@example.com
expect_failure install --prepare-only --local-only --config-dir "$test_root/domain" --port 65536
expect_failure install --prepare-only --local-only --config-dir "$test_root/../escape"
expect_failure registration maybe --config-dir "$test_root/complete"
expect_failure upgrade --prepare-only --config-dir "$test_root/complete"
[[ ! -e "$test_root/domain" ]]
printf 'Installer configuration tests passed.\n'
