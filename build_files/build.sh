#!/bin/bash

set -ouex pipefail

# SOURCE_DATE_EPOCH is provided via the --env flag in the Containerfile build.
# RPM 6.0.1 uses it automatically for deterministic INSTALLTIME/INSTALLTID.

dnf5 -y copr enable abn/throttled
dnf5 -y copr enable sneexy/python-validity
dnf5 -y copr enable lionheartp/Hyprland

dnf5 -y config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo
dnf5 -y install terra-release

dnf5 -y install dnf5-plugin-manifest libpkgmanifest createrepo_c

# Remove packages from base image that conflict with our replacements
dnf5 -y remove thermald tuned tuned-ppd

# Use lockfile-based package management.
# If a pre-generated lockfile (packages.manifest.yaml) exists, use it for the download.
# Otherwise, resolve from the input file first.
if [ -f /ctx/packages.manifest.yaml ]; then
  dnf5 manifest download --manifest /ctx/packages.manifest.yaml
else
  dnf5 manifest resolve --input /ctx/rpms.in.yaml
  dnf5 manifest download
fi

# Create a local repo from downloaded RPMs and install our packages additively
createrepo_c packages.manifest/
dnf5 install -y --nogpgcheck --repofrompath=rpmcache,packages.manifest/ --repo=rpmcache \
  niri noctalia-git wl-mirror wl-clipboard ghostty \
  fprintd-clients fprintd-clients-pam open-fprintd python3-validity \
  tlp tlp-rdw zcfan throttled

# Disable COPRs so they don't end up enabled on the final image:
dnf5 -y copr disable abn/throttled
dnf5 -y copr disable sneexy/python-validity
dnf5 -y copr disable lionheartp/Hyprland

# Early KMS for i915
printf 'force_drivers+=" i915 "\n' | tee /usr/lib/dracut/dracut.conf.d/20-t470s-early-kms.conf
printf 'options i915 enable_guc=2\noptions i915 enable_psr=1\noptions i915 enable_rc6=7\n' | tee /usr/lib/modprobe.d/t470s-i915.conf

kver="$(cd /usr/lib/modules && echo *)"
depmod -a "${kver}"
dracut -vf "/usr/lib/modules/${kver}/initramfs.img" "${kver}"

setsebool -P domain_kernel_load_modules on

systemctl enable tlp.service
systemctl enable zcfan.service
systemctl enable throttled.service
systemctl mask systemd-rfkill.service systemd-rfkill.socket

cat << EOF > /usr/lib/bootc/kargs.d/99-thinkpad-fan-control.toml
kargs = ["thinkpad_acpi.fan_control=1"]
EOF

# Regenerate fontconfig cache deterministically
fc-cache -rs

dnf5 -y remove dnf5-plugin-manifest libpkgmanifest createrepo_c
dnf5 clean all

rm -rf packages.manifest/ packages.manifest.yaml
