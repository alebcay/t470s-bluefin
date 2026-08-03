#!/bin/bash
set -euo pipefail

# Enable/disable the third-party repos that t470s-bluefin's RPM lockfile
# depends on. Shared by the image build (build.sh), the daily lockfile
# regeneration (update-lockfile.yml) and local `just resolve-lockfile` so the
# repo setup cannot drift between them.
#
# Usage:
#   install-repos.sh enable   # add repos and the lockfile tooling
#   install-repos.sh disable  # turn COPRs back off (end of image build)

ACTION="${1:-enable}"

case "$ACTION" in
  enable)
    dnf5 -y config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo
    dnf5 -y install terra-release
    dnf5 -y copr enable abn/throttled
    dnf5 -y copr enable sneexy/python-validity
    dnf5 -y copr enable lionheartp/Hyprland
    dnf5 -y install dnf5-plugin-manifest libpkgmanifest
    ;;
  disable)
    dnf5 -y copr disable abn/throttled
    dnf5 -y copr disable sneexy/python-validity
    dnf5 -y copr disable lionheartp/Hyprland
    ;;
  *)
    echo "Usage: $0 [enable|disable]" >&2
    exit 1
    ;;
esac
