#!/usr/bin/env bash
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bundle_dir="$script_dir"
if [[ ! -x "$bundle_dir/bin/manager" ]]; then
    bundle_dir="$(cd -- "$script_dir/../.." && pwd)"
fi
exec "$bundle_dir/bin/manager" --bundle-dir "$bundle_dir" "$@"
