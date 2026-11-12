#!/usr/bin/env bash
set -euo pipefail

remote=devops
remote_dir=/var/www/devops-site
site_url=https://devops.local
ca_cert="$HOME/devops.crt"
options=(-avz --checksum --delete --chmod=D755,F644)

case "$#" in
    0) ;;
    1) [[ "$1" == --dry-run ]] || { echo "Usage: $0 [--dry-run]" >&2; exit 1; }
       options+=(--dry-run) ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 1 ;;
esac

repo=$(git rev-parse --show-toplevel)
if [[ ! -f "$repo/site/index.html" ]]; then
    echo 'site/index.html is missing' >&2
    exit 1
fi
if [[ -n "$(git -C "$repo" status --porcelain --untracked-files=normal)" ]]; then
    echo 'Commit or remove working tree changes before deployment' >&2
    exit 1
fi
commit=$(git -C "$repo" rev-parse --short HEAD)
if ! rsync "${options[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' -- "$repo/site/" "$remote:$remote_dir/"; then
    echo 'Site synchronization failed' >&2
    exit 1
fi

if [[ "$#" == 1 ]]; then
    exit 0
fi
if ! curl --noproxy devops.local --fail --silent --show-error --max-time 10 --cacert "$ca_cert" --output /dev/null "$site_url"; then
    echo 'HTTPS availability check failed' >&2
    exit 1
fi
printf 'Deployed commit %s\n' "$commit"
