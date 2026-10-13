#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/vultr-ip-sync.sh"
bash -n "$ROOT/vultr-ip-add.sh"
bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"
bash -n "$ROOT/bootstrap.sh"

if command -v shellcheck >/dev/null; then
  shellcheck "$ROOT/vultr-ip-sync.sh" "$ROOT/vultr-ip-add.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/bootstrap.sh"
fi

! grep -Rni 'VULTR_API_KEY\|api.vultr.com' "$ROOT" \
  --exclude-dir=.git --exclude=test.sh

checksum() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

expected_install=$(sed -n 's/^readonly INSTALL_SHA256="\([a-f0-9]*\)"$/\1/p' "$ROOT/bootstrap.sh")
expected_sync=$(sed -n 's/^readonly SYNC_SHA256="\([a-f0-9]*\)"$/\1/p' "$ROOT/bootstrap.sh")
expected_add=$(sed -n 's/^readonly ADD_SHA256="\([a-f0-9]*\)"$/\1/p' "$ROOT/bootstrap.sh")
[[ $(checksum "$ROOT/install.sh") == "$expected_install" ]]
[[ $(checksum "$ROOT/vultr-ip-sync.sh") == "$expected_sync" ]]
[[ $(checksum "$ROOT/vultr-ip-add.sh") == "$expected_add" ]]

echo 'tests passed'
