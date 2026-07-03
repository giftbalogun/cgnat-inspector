#!/usr/bin/env bash
# install.sh
# Installs CGNAT Inspector into /usr/local/bin (or a custom PREFIX).
#
# Usage:
#   sudo ./install.sh
#   PREFIX=/opt/cgnat-inspector ./install.sh   # custom location

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"
SHARE_DIR="${PREFIX}/share/cgnat-inspector"

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

info()  { printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
error() { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[32m[OK]\033[0m %s\n' "$*"; }

if [[ ! -f "${SCRIPT_DIR}/cgnat-inspector" ]]; then
    error "Cannot find cgnat-inspector in ${SCRIPT_DIR}. Run this script from the repository root."
    exit 1
fi

if [[ ! -w "${PREFIX}" && "${EUID}" -ne 0 ]]; then
    error "No write permission to ${PREFIX}. Try: sudo ./install.sh"
    exit 1
fi

info "Installing ${SHARE_DIR} ..."
mkdir -p "${SHARE_DIR}"
cp -r "${SCRIPT_DIR}/lib" "${SHARE_DIR}/lib"
cp "${SCRIPT_DIR}/cgnat-inspector" "${SHARE_DIR}/cgnat-inspector"
chmod +x "${SHARE_DIR}/cgnat-inspector"
find "${SHARE_DIR}/lib" -type f -name '*.sh' -exec chmod 755 {} \;

info "Linking executable into ${BIN_DIR} ..."
mkdir -p "${BIN_DIR}"
ln -sf "${SHARE_DIR}/cgnat-inspector" "${BIN_DIR}/cgnat-inspector"
chmod +x "${BIN_DIR}/cgnat-inspector"

if command -v cgnat-inspector >/dev/null 2>&1; then
    ok "Installed successfully."
    printf '\n'
    "${BIN_DIR}/cgnat-inspector" --version
    printf '\nRun '\''cgnat-inspector --help'\'' to get started.\n'
else
    ok "Installed to ${BIN_DIR}/cgnat-inspector"
    printf '\nNote: %s is not currently on your PATH.\n' "${BIN_DIR}"
    # shellcheck disable=SC2016  # intentional: $PATH shown literally to the user, not expanded here
    printf 'Add this to your shell profile:\n\n    export PATH="%s:$PATH"\n\n' "${BIN_DIR}"
fi
