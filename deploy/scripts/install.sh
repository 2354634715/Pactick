#!/usr/bin/env bash
# Self-hosting entry point. Run from a trusted source checkout on Ubuntu/Debian.
set -Eeuo pipefail
umask 077

fail() { printf 'deployment error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1 (see docs/SELF_HOSTING.md)"; }
usage() {
    cat <<'HELP'
Usage: bash deploy/scripts/install.sh COMMAND [OPTIONS]

Commands:
  install                  Generate private config, build, migrate, start, back up
  upgrade                  Build a new release (backs up before migration)
  registration open|close  Enable/disable new accounts and recreate the API
  backup                   Create a local database backup
  restore-check FILE       Restore a backup into an isolated temporary database
  status                   Check containers, loopback binding and local backup

Options for all commands:
  --config-dir PATH        Config directory (default /opt/pactick/config)
Options for install:
  --local-only             Bind API to loopback; configure your own HTTPS proxy
  --domain HOST            Configure Nginx and a Let's Encrypt certificate
  --email ADDRESS          ACME account contact, required with --domain
  --accept-acme-terms      Explicitly accept Let's Encrypt terms
  --backup-dir PATH        Local backups (default /var/backups/pactick)
  --port NUMBER            Loopback HTTP port (default 8080)
  --prepare-only           Only generate/reuse config; no Docker/system changes

Install requires --local-only OR --domain. Registration starts CLOSED.
Existing complete configs are reused without changing secrets or settings.
Run operational commands as root on Linux with Docker Compose v2 and systemd.
No dependency download scripts, firewall changes, or volume deletion are run.
HELP
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd -- "$script_dir/../.." && pwd)"
command_name="${1:-help}"
if (( $# > 0 )); then shift; fi
config_dir="${PACTICK_CONFIG_DIR:-/opt/pactick/config}"
backup_dir=/var/backups/pactick
http_port=8080
domain=
email=
local_only=false
accept_terms=false
prepare_only=false
operand=
while (( $# > 0 )); do
    case "$1" in
        --config-dir|--backup-dir|--port|--domain|--email)
            (( $# >= 2 )) || fail "$1 requires a value"
            [[ -n "$2" && "$2" != --* ]] || fail "$1 requires a value"
            case "$1" in
                --config-dir) config_dir="$2" ;;
                --backup-dir) backup_dir="$2" ;;
                --port) http_port="$2" ;;
                --domain) domain="$2" ;;
                --email) email="$2" ;;
            esac
            shift 2 ;;
        --local-only) local_only=true; shift ;;
        --accept-acme-terms) accept_terms=true; shift ;;
        --prepare-only) prepare_only=true; shift ;;
        -h|--help) usage; exit 0 ;;
        --*) fail "unknown option: $1" ;;
        *) [[ -z "$operand" ]] || fail "unexpected argument: $1"; operand="$1"; shift ;;
    esac
done
case "$command_name" in
    help|-h|--help) usage; exit 0 ;;
    install|upgrade|registration|backup|restore-check|status) ;;
    *) fail "unknown command: $command_name" ;;
esac
case "$command_name" in
    registration) [[ "$operand" == open || "$operand" == close ]] || fail "use registration open|close" ;;
    restore-check) [[ -n "$operand" ]] || fail "restore-check requires a dump path" ;;
    *) [[ -z "$operand" ]] || fail "unexpected argument: $operand" ;;
esac
if [[ "$command_name" != install ]]; then
    [[ "$prepare_only" == false && "$local_only" == false && -z "$domain$email" && "$accept_terms" == false && "$backup_dir" == /var/backups/pactick && "$http_port" == 8080 ]] ||
        fail "install options cannot be used with $command_name"
fi

# Restrict paths used in shell-sourced env files and systemd units, before writes.
validate_path() {
    [[ "$1" =~ ^/[a-zA-Z0-9_./-]+$ && "$1" != / && "$1" != */../* && "$1" != */.. && "$1" != */./* && "$1" != */. ]] ||
        fail "use a specific absolute path with letters, digits, _, -, / and .: $1"
}
validate_path "$config_dir"
validate_path "$backup_dir"
[[ "$http_port" =~ ^[1-9][0-9]{0,4}$ ]] && (( http_port <= 65535 )) || fail "port must be 1..65535"
if [[ "$command_name" == install ]]; then
    if [[ -n "$domain" ]]; then
        [[ "$local_only" == false ]] || fail "choose --domain or --local-only"
        [[ ${#domain} -le 253 && "$domain" == *.* && "$domain" != *..* ]] || fail "invalid DNS hostname"
        IFS='.' read -ra labels <<< "$domain"
        for label in "${labels[@]}"; do
            [[ "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || fail "invalid DNS hostname"
        done
        [[ "$domain" != *. && ! "$domain" =~ ^[0-9.]+$ ]] || fail "provide a DNS hostname, not an IP"
        [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || fail "provide --email for ACME"
        [[ "$accept_terms" == true ]] || fail "--accept-acme-terms is required for certificate registration"
    else
        [[ "$local_only" == true ]] || fail "choose --local-only or --domain HOST"
        [[ -z "$email" && "$accept_terms" == false ]] || fail "ACME options require --domain"
    fi
fi

need openssl
if [[ "$prepare_only" == false ]]; then
    [[ "$(uname -s)" == Linux ]] || fail "deployment requires Linux; --prepare-only can generate config elsewhere"
    (( EUID == 0 )) || fail "run operational commands with sudo"
    validate_path "$app_dir"
    for tool in docker curl stat flock; do need "$tool"; done
    docker compose version >/dev/null 2>&1 || fail "install Docker Compose v2"
    docker info >/dev/null 2>&1 || fail "Docker daemon is unavailable"
    if [[ "$command_name" == install ]]; then
        need systemctl
        [[ -d /run/systemd/system ]] || fail "install requires a running systemd system"
        if [[ -n "$domain" ]]; then
            for tool in nginx certbot envsubst; do need "$tool"; done
        fi
    fi
fi

[[ -f "$app_dir/compose.production.yaml" ]] || fail "run from the full source checkout"
[[ ! -L "$config_dir" ]] || fail "config directory must not be a symlink"
mkdir -p -- "$config_dir"
if [[ "$prepare_only" == false ]]; then
    # Serializes this entry point. Direct maintenance scripts must not run concurrently.
    [[ ! -L "$config_dir/.deployment.lock" ]] || fail "deployment lock must not be a symlink"
    exec 9>"$config_dir/.deployment.lock"
    flock -n 9 || fail "another deployment command is running"
fi
staging_dir=
candidate_compose_env=
cleanup() {
    [[ -z "$candidate_compose_env" ]] || rm -f -- "$candidate_compose_env"
    if [[ -n "$staging_dir" ]]; then
        # Only remove the four generated files, never a recursively computed path.
        rm -f -- "$staging_dir/api.env" "$staging_dir/postgres.env" "$staging_dir/compose.env" "$staging_dir/backup.env"
        rmdir -- "$staging_dir" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'printf "Command failed. Existing database volumes and backups were retained.\n" >&2' ERR

config_count=0
for file in api.env postgres.env compose.env backup.env; do
    [[ ! -L "$config_dir/$file" ]] || fail "config file must not be a symlink: $file"
    [[ ! -e "$config_dir/$file" || -f "$config_dir/$file" ]] || fail "config file must be a regular file: $file"
    if [[ -f "$config_dir/$file" ]]; then config_count=$((config_count + 1)); fi
done
if (( config_count != 0 && config_count != 4 )); then
    fail "partial config exists; restore the missing files before retrying (secrets will not be regenerated)"
fi

new_image() { printf 'pactick-api:%s-%s' "$(date -u +%Y%m%dT%H%M%S)" "$(openssl rand -hex 4)"; }
if (( config_count == 0 )); then
    [[ "$command_name" == install ]] || fail "no configuration; run install first"
    chmod 0700 "$config_dir"
    staging_dir="$(mktemp -d "$config_dir/.init.XXXXXX")"
    database_password="$(openssl rand -hex 32)"
    jwt_secret="$(openssl rand -hex 64)"
    cat > "$staging_dir/postgres.env" <<EOF
POSTGRES_DB=pactick
POSTGRES_USER=pactick
POSTGRES_PASSWORD=$database_password
EOF
    cat > "$staging_dir/api.env" <<EOF
APP_ENV=production
HTTP_ADDRESS=:8080
DATABASE_URL=postgres://pactick:$database_password@postgres:5432/pactick?sslmode=disable
AUTH_JWT_SECRET=$jwt_secret
ACCESS_TOKEN_TTL=15m
REFRESH_TOKEN_TTL=720h
AUTO_MIGRATE=false
REGISTRATION_ENABLED=false
DB_MAX_CONNS=10
SHUTDOWN_TIMEOUT=15s
ALLOWED_ORIGINS=
CLIENT_UPDATE_MANIFEST_JSON=
EOF
    cat > "$staging_dir/compose.env" <<EOF
PACTICK_IMAGE=$(new_image)
PACTICK_CONFIG_DIR=$config_dir
PACTICK_HTTP_PORT=$http_port
PACTICK_DOCKERFILE=Dockerfile
POSTGRES_IMAGE=postgres:17-alpine
EOF
    printf 'PACTICK_BACKUP_ROOT=%s\n' "$backup_dir" > "$staging_dir/backup.env"
    for file in api.env postgres.env compose.env backup.env; do
        chmod 0600 "$staging_dir/$file"
        mv -n -- "$staging_dir/$file" "$config_dir/$file"
    done
    unset database_password jwt_secret
    printf 'Generated private configuration in %s (registration closed).\n' "$config_dir"
else
    printf 'Reusing existing configuration; credentials and configured port/backup path are preserved.\n'
fi
if [[ "$prepare_only" == true ]]; then
    printf 'Preparation complete. No containers or system services were changed.\n'
    exit 0
fi

export PACTICK_APP_DIR="$app_dir" PACTICK_CONFIG_DIR="$config_dir" PACTICK_COMPOSE_ENV="$config_dir/compose.env"
bash "$script_dir/validate-config.sh"
set -a
# These are locally generated administrator-owned shell-compatible files.
# shellcheck disable=SC1090
source "$config_dir/compose.env"
# shellcheck disable=SC1090
source "$config_dir/backup.env"
set +a
[[ "$PACTICK_CONFIG_DIR" == "$config_dir" ]] || fail "compose.env points at a different config directory"
compose=(docker compose --project-directory "$app_dir" --env-file "$config_dir/compose.env" -f "$app_dir/compose.production.yaml")

replace_value() {
    local file="$1" key="$2" value="$3" temporary
    temporary="$(mktemp "$config_dir/.edit.XXXXXX")"
    awk -v key="$key" -v value="$value" 'BEGIN {found=0} index($0,key "=")==1 {print key "=" value; found=1; next} {print} END {if (!found) print key "=" value}' "$file" > "$temporary"
    chmod 0600 "$temporary"
    mv -- "$temporary" "$file"
}

configure_https() (
    local available=/etc/nginx/sites-available/pactick.conf
    local enabled=/etc/nginx/sites-enabled/pactick.conf
    local challenge_available=/etc/nginx/sites-available/pactick-acme.conf
    local challenge_enabled=/etc/nginx/sites-enabled/pactick-acme.conf
    local marker='# Managed by Pactick install.sh'
    # A separately managed site must be reviewed and migrated by its owner.
    [[ ! -e "$available" ]] || grep -Fqx "$marker" "$available" || fail "existing Nginx site is not managed by this installer: $available"
    [[ ! -L "$available" ]] || fail "Nginx site must not be a symlink"
    if [[ -e "$enabled" || -L "$enabled" ]]; then
        [[ -L "$enabled" && "$(readlink "$enabled")" == "$available" ]] || fail "unexpected Nginx enabled site"
    fi
    # Nginx workers must be able to traverse the challenge directory. The
    # installer otherwise uses a private umask for secrets and backups.
    install -d -m 0755 /etc/nginx/sites-available /etc/nginx/sites-enabled /var/www/pactick-acme
    [[ ! -e "$challenge_available" && ! -L "$challenge_available" && ! -e "$challenge_enabled" && ! -L "$challenge_enabled" ]] ||
        fail "temporary ACME site already exists; inspect it before retrying"
    local rollback_file candidate_file
    local had_site=false created_link=false challenge_created=false committed=false candidate_installed=false
    rollback_file="$(mktemp /etc/nginx/sites-available/.pactick-rollback.XXXXXX)"
    candidate_file="$(mktemp /etc/nginx/sites-available/.pactick-candidate.XXXXXX)"
    if [[ -f "$available" ]]; then
        had_site=true
        cp -- "$available" "$rollback_file"
    fi
    cleanup_https() {
        local status=$?
        if [[ "$challenge_created" == true ]]; then
            rm -f -- "$challenge_enabled" "$challenge_available"
        fi
        if [[ "$committed" == false ]]; then
            if [[ "$candidate_installed" == true ]]; then
                if [[ "$had_site" == true ]]; then
                    chmod 0644 "$rollback_file"
                    mv -- "$rollback_file" "$available"
                else
                    rm -f -- "$available"
                fi
            fi
            [[ "$created_link" == false ]] || rm -f -- "$enabled"
            if nginx -t >/dev/null 2>&1; then systemctl reload nginx >/dev/null 2>&1 || true; fi
            printf 'HTTPS setup failed; the previous Nginx site configuration was retained.\n' >&2
        fi
        rm -f -- "$rollback_file" "$candidate_file"
        exit "$status"
    }
    trap cleanup_https EXIT
    export API_DOMAIN="$domain" PACTICK_HTTP_PORT
    # A separate HTTP challenge site leaves an existing HTTPS domain running.
    if [[ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        challenge_created=true
        { printf '%s\n' "$marker"; envsubst '${API_DOMAIN}' < "$app_dir/deploy/nginx/pactick-http.conf.template"; } > "$challenge_available"
        chmod 0644 "$challenge_available"
        ln -s "$challenge_available" "$challenge_enabled"
        nginx -t
        systemctl enable --now nginx
        systemctl reload nginx
    fi
    (
        umask 022
        certbot certonly --webroot -w /var/www/pactick-acme --non-interactive \
            --agree-tos --email "$email" --cert-name "$domain" -d "$domain" --keep-until-expiring
    )
    { printf '%s\n' "$marker"; envsubst '${API_DOMAIN} ${PACTICK_HTTP_PORT}' < "$app_dir/deploy/nginx/pactick-https.conf.template"; } > "$candidate_file"
    chmod 0644 "$candidate_file"
    mv -- "$candidate_file" "$available"
    candidate_installed=true
    if [[ ! -L "$enabled" ]]; then
        ln -s "$available" "$enabled"
        created_link=true
    fi
    if [[ "$challenge_created" == true ]]; then
        rm -f -- "$challenge_enabled" "$challenge_available"
        challenge_created=false
    fi
    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
    install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
    printf '#!/usr/bin/env bash\nset -e\nnginx -t\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/pactick-nginx.sh
    chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/pactick-nginx.sh
    systemctl enable --now certbot.timer
    committed=true
)

case "$command_name" in
    install|upgrade)
        if [[ "$command_name" == upgrade ]]; then
            # Keep the last successful image available for later operations.
            candidate_compose_env="$(mktemp "$config_dir/.release-compose.XXXXXX")"
            cp -- "$config_dir/compose.env" "$candidate_compose_env"
            replace_value "$candidate_compose_env" PACTICK_IMAGE "$(new_image)"
            PACTICK_COMPOSE_ENV="$candidate_compose_env" \
                PACTICK_RELEASE_CONFIG_TARGET="$config_dir/compose.env" bash "$script_dir/release.sh"
        else
            bash "$script_dir/release.sh"
        fi
        if [[ "$command_name" == install ]]; then
            # The checkout stays in this location for scheduled backups.
            cat > /etc/systemd/system/pactick-backup.service <<EOF
[Unit]
Description=Pactick local PostgreSQL backup
Requires=docker.service
After=docker.service
[Service]
Type=oneshot
User=root
UMask=0077
WorkingDirectory=$app_dir
Environment=PACTICK_APP_DIR=$app_dir
Environment=PACTICK_CONFIG_DIR=$config_dir
ExecStart=/bin/bash $script_dir/backup.sh daily
EOF
            chmod 0644 /etc/systemd/system/pactick-backup.service
            install -m 0644 "$app_dir/deploy/systemd/pactick-backup.timer" /etc/systemd/system/pactick-backup.timer
            systemctl daemon-reload
            systemctl enable --now pactick-backup.timer
            systemctl start pactick-backup.service
            if [[ -n "$domain" ]]; then configure_https; fi
        fi
        if [[ -n "$domain" ]]; then export PACTICK_PUBLIC_URL="https://$domain"; fi
        bash "$script_dir/verify-deployment.sh"
        printf '\nReady. API loopback port: %s. Config: %s\n' "$PACTICK_HTTP_PORT" "$config_dir"
        printf 'Open registration only while creating accounts; then run registration close.\n'
        ;;
    registration)
        [[ ! -e "$config_dir/.release-pending" && ! -L "$config_dir/.release-pending" ]] ||
            fail "a release started database migration but did not finish; resolve it with upgrade or the recovery procedure in docs/SELF_HOSTING.md before changing registration"
        registration=false
        [[ "$operand" != open ]] || registration=true
        replace_value "$config_dir/api.env" REGISTRATION_ENABLED "$registration"
        "${compose[@]}" up -d --no-deps --force-recreate --wait --wait-timeout 90 api
        printf 'REGISTRATION_ENABLED=%s\n' "$registration"
        ;;
    backup) bash "$script_dir/backup.sh" daily ;;
    restore-check) bash "$script_dir/restore-check.sh" "$operand" ;;
    status) bash "$script_dir/verify-deployment.sh" ;;
esac
