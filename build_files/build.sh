#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

dnf5 -y copr enable abn/throttled
dnf5 -y copr enable sneexy/python-validity

dnf5 -y config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo
dnf5 -y install terra-release
dnf5 -y install niri noctalia-shell
dnf5 -y install fprintd-clients fprintd-clients-pam open-fprintd python3-validity

dnf5 -y remove thermald tuned tuned-ppd
dnf5 -y install tlp tlp-rdw zcfan
dnf5 -y install throttled

# Disable COPRs so they don't end up enabled on the final image:
dnf5 -y copr disable abn/throttled
dnf5 -y copr disable sneexy/python-validity

systemctl enable tlp.service
systemctl mask systemd-rfkill.service systemd-rfkill.socket

cat << EOF > /usr/lib/bootc/kargs.d/99-thinkpad-fan-control.toml
kargs = ["thinkpad_acpi.fan_control=1"]
EOF
