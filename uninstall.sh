#!/usr/bin/env bash
# uninstall.sh
# Removes CGNAT Inspector, installed by install.sh.
#
# Usage:
#   sudo ./uninstall.sh
#   PREFIX=/opt/cgnat-inspector ./uninstall.sh   # matches a custom install

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"
SHARE_DIR="${PREFIX}/share/cgnat-inspector"

info()  { printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[32m[OK]\033[0m %s\n' "$*"; }

if [[ ! -w "${PREFIX}" && "${EUID}" -ne 0 ]]; then
    error "No write permission to ${PREFIX}. Try: sudo ./uninstall.sh"
    exit 1
fi

removed=false

if [[ -L "${BIN_DIR}/cgnat-inspector" || -f "${BIN_DIR}/cgnat-inspector" ]]; then
    info "Removing ${BIN_DIR}/cgnat-inspector ..."
    rm -f "${BIN_DIR}/cgnat-inspector"
    removed=true
fi

if [[ -d "${SHARE_DIR}" ]]; then
    info "Removing ${SHARE_DIR} ..."
    rm -rf "${SHARE_DIR}"
    removed=true
fi

if [[ "${removed}" == "true" ]]; then
    ok "CGNAT Inspector has been uninstalled."
else
    info "CGNAT Inspector does not appear to be installed under ${PREFIX}."
fi
