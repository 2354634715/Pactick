#!/usr/bin/env bash
set -Eeuo pipefail
fail() { printf 'server error: %s\n' "$*" >&2; exit 1; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundle_dir="$script_dir"
if [[ ! -x "$bundle_dir/bin/server" ]]; then
    bundle_dir="$(cd -- "$script_dir/../.." && pwd)"
fi
config_file="$bundle_dir/data/api.env"
program=server
while (( $# > 0 )); do
    case "$1" in
        --config-file)
            (( $# >= 2 )) || fail '--config-file requires a path'
            config_file="$2"; shift 2 ;;
        --migrate-only) program=migrate; shift ;;
        *) fail "unknown argument: $1" ;;
    esac
done
[[ -f "$config_file" ]] || fail 'configuration is missing; initialize native mode in the manager or pass --config-file'
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]] || fail 'invalid configuration line; expected a literal KEY=value assignment'
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ ${#value} -ge 2 && ( "$value" == \"*\" || "$value" == \'*\' ) ]]; then
        value="${value:1:${#value}-2}"
    fi
    export "$key=$value"
done < "$config_file"
exec "$bundle_dir/bin/$program"
