#!/usr/bin/env bash
# Exercise the installer's real HTTPS function with isolated files and mocked
# service commands. No Docker, root, real /etc, ACME or Nginx process is used.
set -Eeuo pipefail

# Git Bash otherwise implements ln -s by copying files, which cannot verify
# the installer's symlink checks. Linux uses its normal symlink implementation.
case "$(uname -s)" in
    MINGW*|MSYS*) export MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict" ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "$script_dir/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/pactick-https.XXXXXX")"
test_root="$(realpath "$test_root")"
temp_root="$(realpath "${TMPDIR:-/tmp}")"
cleanup() {
    [[ "$test_root" == "$temp_root"/pactick-https.* && "$test_root" != "$temp_root" ]] || return 1
    rm -rf -- "$test_root"
}
trap cleanup EXIT

# The production literals being replaced are unquoted, space-free paths.
# Fail safely if the harness cannot preserve those shell semantics.
[[ ! "$test_root" =~ [[:space:]] ]] || {
    printf 'Set TMPDIR to a directory without whitespace for this test.\n' >&2
    exit 1
}

# Anchor both ends. A refactor of this function should fail this extraction,
# rather than silently run an old copy or source the installer's entry point.
awk '
    /^configure_https\(\) \($/ { if (found++) exit 3; active=1 }
    active { print }
    active && /^\)$/ { active=0; complete++ }
    END { if (found != 1 || complete != 1 || active) exit 4 }
' "$app_dir/deploy/scripts/install.sh" > "$test_root/https-original.sh"

# Every system path in the extracted function is redirected before execution.
# The templates are read from the checkout, but are only written under the
# temporary root. Their rendered certificate paths are configuration text.
sed -e 's|/etc/|${HTTPS_ROOT}/etc/|g' \
    -e 's|/var/www/|${HTTPS_ROOT}/var/www/|g' \
    "$test_root/https-original.sh" > "$test_root/https-isolated.sh"
if grep -Eq '(^|[[:space:]"=])/((etc|var)/)' "$test_root/https-isolated.sh"; then
    printf 'Found an unisolated system path in the HTTPS function.\n' >&2
    exit 1
fi
bash -n "$test_root/https-isolated.sh"

cat > "$test_root/run-case.sh" <<'HARNESS'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
app_dir="$CHECKOUT_ROOT"
domain=new.example.test
email=admin@example.test
PACTICK_HTTP_PORT=8093
available="$HTTPS_ROOT/etc/nginx/sites-available/pactick.conf"
enabled="$HTTPS_ROOT/etc/nginx/sites-enabled/pactick.conf"
challenge="$HTTPS_ROOT/etc/nginx/sites-enabled/pactick-acme.conf"

fail() { printf 'test deployment error: %s\n' "$*" >&2; exit 1; }
event() { printf '%s\n' "$*" >> "$HTTPS_ROOT/events"; }
has_candidate() { [[ -f "$available" ]] && grep -Fq 'server_name new.example.test;' "$available"; }

# Keep the actual file writes, chmod, symlinks and rollback moves. Mock only
# external commands that would contact the network or control the host.
envsubst() {
    local content
    content="$(cat)"
    content="${content//\$\{API_DOMAIN\}/$API_DOMAIN}"
    if [[ "$*" == *PACTICK_HTTP_PORT* ]]; then
        content="${content//\$\{PACTICK_HTTP_PORT\}/$PACTICK_HTTP_PORT}"
    fi
    printf '%s\n' "$content"
}
nginx() {
    [[ "$*" == -t ]] || fail "unexpected nginx arguments: $*"
    event NGINX_TEST
    if [[ "$FAIL_STAGE" == nginx ]] && has_candidate && [[ ! -e "$HTTPS_ROOT/injected" ]]; then
        : > "$HTTPS_ROOT/injected"
        event NGINX_REJECTED_CANDIDATE
        return 61
    fi
}
systemctl() {
    case "$*" in
        'enable --now nginx'|'enable --now certbot.timer') event "SYSTEMCTL $*" ;;
        'reload nginx')
            if [[ "$FAIL_STAGE" == reload ]] && has_candidate && [[ ! -e "$HTTPS_ROOT/injected" ]]; then
                : > "$HTTPS_ROOT/injected"
                event RELOAD_REJECTED_CANDIDATE
                return 62
            fi
            if has_candidate; then event RELOAD_NEW_SITE; else event RELOAD_ORIGINAL_SITE; fi
            ;;
        *) fail "unexpected systemctl arguments: $*" ;;
    esac
}
certbot() {
    [[ "$*" == *"--webroot -w $HTTPS_ROOT/var/www/pactick-acme"* ]] || fail "unisolated Certbot webroot"
    event CERTBOT
    if [[ -f "$HTTPS_ROOT/original-site" ]]; then
        cmp -- "$HTTPS_ROOT/original-site" "$available" || fail "old site changed before ACME succeeded"
        [[ -L "$enabled" ]] || fail "old HTTPS site was disabled before ACME succeeded"
    fi
    if [[ ! -f "$HTTPS_ROOT/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        [[ -L "$challenge" ]] || fail "HTTP challenge site was not enabled"
    fi
    [[ "$(umask)" == 0022 ]] || fail "ACME challenge files must be publicly readable"
    if [[ "$FAIL_STAGE" == acme ]]; then event ACME_REJECTED; return 63; fi
    mkdir -p -- "$HTTPS_ROOT/etc/letsencrypt/live/$domain"
    printf 'test certificate\n' > "$HTTPS_ROOT/etc/letsencrypt/live/$domain/fullchain.pem"
}

# shellcheck disable=SC1090
source "$EXTRACTED_FUNCTION"
configure_https
HARNESS

case_count=0
run_case() {
    local name="$1" existing="$2" fail_stage="$3" expected="$4" existing_certificate="${5:-false}"
    local root="$test_root/$name" status=0
    mkdir -p -- "$root/etc/nginx/sites-available" "$root/etc/nginx/sites-enabled"
    local available="$root/etc/nginx/sites-available/pactick.conf"
    local enabled="$root/etc/nginx/sites-enabled/pactick.conf"
    if [[ "$existing" == true ]]; then
        cat > "$root/original-site" <<'SITE'
# Managed by Pactick install.sh
# Original bytes, including this separate comment, must survive failure.
server {
    listen 443 ssl;
    server_name old.example.test;
}
SITE
        cp -- "$root/original-site" "$available"
        ln -s "$available" "$enabled"
    fi
    if [[ "$existing_certificate" == true ]]; then
        mkdir -p -- "$root/etc/letsencrypt/live/new.example.test"
        printf 'existing certificate\n' > "$root/etc/letsencrypt/live/new.example.test/fullchain.pem"
    fi

    HTTPS_ROOT="$root" CHECKOUT_ROOT="$app_dir" \
        EXTRACTED_FUNCTION="$test_root/https-isolated.sh" FAIL_STAGE="$fail_stage" \
        bash "$test_root/run-case.sh" > "$root/output" 2>&1 || status=$?
    trap 'printf "HTTPS assertion failed: %s\n" "$name" >&2; cat "$root/output" >&2' ERR
    if [[ "$expected" == success ]]; then
        [[ "$status" == 0 ]] || { cat "$root/output" >&2; return 1; }
        grep -Fq 'server_name new.example.test;' "$available"
        grep -Fq 'server 127.0.0.1:8093;' "$available"
        grep -Fq 'proxy_set_header Host $host;' "$available"
        [[ -L "$enabled" && "$(readlink "$enabled")" == "$available" ]]
        [[ -x "$root/etc/letsencrypt/renewal-hooks/deploy/pactick-nginx.sh" ]]
        grep -Fxq RELOAD_NEW_SITE "$root/events"
        grep -Fxq 'SYSTEMCTL enable --now certbot.timer' "$root/events"
    else
        [[ "$status" != 0 ]] || { printf '%s unexpectedly succeeded\n' "$name" >&2; return 1; }
        if [[ "$existing" == true ]]; then
            cmp -- "$root/original-site" "$available"
            [[ -L "$enabled" && "$(readlink "$enabled")" == "$available" ]]
            [[ "$(tail -n 1 "$root/events")" == RELOAD_ORIGINAL_SITE ]]
        else
            [[ ! -e "$available" && ! -L "$available" && ! -e "$enabled" && ! -L "$enabled" ]]
        fi
        grep -Fq 'previous Nginx site configuration was retained' "$root/output"
        case "$fail_stage" in
            acme) grep -Fxq ACME_REJECTED "$root/events" ;;
            nginx) grep -Fxq NGINX_REJECTED_CANDIDATE "$root/events" ;;
            reload) grep -Fxq RELOAD_REJECTED_CANDIDATE "$root/events" ;;
        esac
    fi
    # Verify both regular temporary files and dangling enabled symlinks are gone.
    [[ -z "$(find "$root/etc/nginx" \( -name '.pactick-*' -o -name 'pactick-acme.conf' \) -print)" ]]
    if [[ "$(uname -s)" == Linux ]]; then
        [[ "$(stat -c '%a' "$root/var/www/pactick-acme")" == 755 ]]
    fi
    case_count=$((case_count + 1))
    printf 'HTTPS case passed: %s\n' "$name"
    trap - ERR
}

run_case acme_preserves_existing true acme failure
run_case config_test_restores_existing true nginx failure
run_case reload_restores_existing true reload failure
run_case first_acme_failure false acme failure
run_case first_config_test_failure false nginx failure
run_case first_reload_failure false reload failure
run_case first_install_success false none success
run_case replacement_success true none success
run_case existing_certificate_retry true none success true
printf 'HTTPS isolation and rollback tests passed (%s cases).\n' "$case_count"
