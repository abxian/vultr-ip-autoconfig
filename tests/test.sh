#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/vultr-ip-sync.sh"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"

if command -v shellcheck >/dev/null; then
  shellcheck "$ROOT/vultr-ip-sync.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh"
fi

grep -q 'Existing addresses are never removed' "$ROOT/vultr-ip-sync.sh"

echo 'tests passed'
