#!/usr/bin/env bash
# lib/version.sh
# Central version information for CGNAT Inspector.
# Bump CGNAT_VERSION on every release and update CHANGELOG.md accordingly.

if [[ -n "${CGNAT_VERSION_LOADED:-}" ]]; then
    return 0
fi
CGNAT_VERSION_LOADED=1

readonly CGNAT_VERSION="1.1.0"
readonly CGNAT_NAME="CGNAT Inspector"
# shellcheck disable=SC2034  # consumed by cgnat-inspector's print_help()
readonly CGNAT_REPO_URL="https://github.com/giftbalogun/cgnat-inspector"

print_version() {
    printf '%s v%s\n' "${CGNAT_NAME}" "${CGNAT_VERSION}"
}
