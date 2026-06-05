#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

dnf5 -y copr enable abn/throttled
dnf5 -y copr enable sneexy/python-validity
dnf5 -y copr enable lionheartp/Hyprland

dnf5 -y config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo
dnf5 -y install terra-release
# dnf5 -y install niri noctalia-shell
dnf5 -y install niri noctalia-git
dnf5 -y install fprintd-clients fprintd-clients-pam open-fprintd python3-validity

# Erase stock kernel from base image, then install the pre-built cachyos
# kernel RPM (built in the build_kernel CI job).
export DRACUT_NO_XATTR=1
_oldkver="$(rpm -q --queryformat "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core 2>/dev/null || true)"
if [ -n "$_oldkver" ]; then
  rpm --erase kernel kernel-core kernel-modules --nodeps
  rm -rf "/lib/modules/${_oldkver}"
fi

rpm -ivh --noscripts --nodeps /ctx/kernel-rpms/*.rpm

kver="$(cd /usr/lib/modules && echo *)"
depmod -a "${kver}"
printf 'export DRACUT_NO_XATTR=1\nreproducible=yes\nadd_dracutmodules+=" bootc ostree "' | tee /usr/lib/dracut/dracut.conf.d/20-t470s-bluefin-cachyos-kernel.conf
dracut -vf "/usr/lib/modules/${kver}/initramfs.img" "${kver}"

setsebool -P domain_kernel_load_modules on

dnf5 -y remove thermald tuned tuned-ppd
dnf5 -y install tlp tlp-rdw zcfan
dnf5 -y install throttled

# Disable COPRs so they don't end up enabled on the final image:
dnf5 -y copr disable abn/throttled
dnf5 -y copr disable sneexy/python-validity
dnf5 -y copr disable lionheartp/Hyprland

systemctl enable tlp.service
systemctl enable zcfan.service
systemctl enable throttled.service
systemctl mask systemd-rfkill.service systemd-rfkill.socket

cat << EOF > /usr/lib/bootc/kargs.d/99-thinkpad-fan-control.toml
kargs = ["thinkpad_acpi.fan_control=1"]
EOF

dnf5 clean all
