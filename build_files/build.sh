#!/bin/bash

set -ouex pipefail

# SOURCE_DATE_EPOCH is provided via the --env flag in the Containerfile build.
# RPM 6.0.1 uses it automatically for deterministic INSTALLTIME/INSTALLTID.

bash /ctx/install-repos.sh enable

dnf5 -y install createrepo_c

# Remove packages from base image that conflict with this image's choices
# (power management replacements, GNOME desktop strip) — see rpms.remove.yaml.
# The final dnf5 remove of build tooling stays inline since it is build-time
# hygiene, not image intent.
REMOVE_PACKAGES=$(python3 -c "
import yaml
with open('/ctx/rpms.remove.yaml') as f:
    print(' '.join(yaml.safe_load(f)['packages']))
")
dnf5 -y remove ${REMOVE_PACKAGES}

# Use lockfile-based package management with download cache.
CACHE_DIR=/rpm-cache
if [ -d "$CACHE_DIR" ] && [ -n "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]; then
  echo "RPM cache hit — using cached downloads"
  mkdir -p packages.manifest
  cp -a "$CACHE_DIR"/* packages.manifest/
else
  echo "RPM cache miss — downloading from repos"
  dnf5 manifest download --manifest /ctx/packages.manifest.yaml
  mkdir -p "$CACHE_DIR"
  cp -a packages.manifest/* "$CACHE_DIR"/
fi

# Create a local repo from downloaded RPMs and install our packages additively
createrepo_c packages.manifest/
PACKAGES=$(python3 -c "
import yaml
with open('/ctx/rpms.in.yaml') as f:
    print(' '.join(yaml.safe_load(f)['packages']))
")
dnf5 install -y --nogpgcheck --repofrompath=rpmcache,packages.manifest/ --repo=rpmcache $PACKAGES

# ---------------------------------------------------------------------------
# GrapheneOS hardened_malloc (light variant), following secureblue's layered
# activation model:
#   1. /etc/ld.so.preload is root-only readable (umask 077). Root-owned
#      processes preload from this file. Unprivileged processes cannot read
#      it, so they can opt out by clearing LD_PRELOAD.
#   2. systemd DefaultEnvironment gives all services LD_PRELOAD.
#   3. pam_env sets LD_PRELOAD for login sessions.
# The library name without a path lets glibc pick the best microarchitecture
# build from /usr/lib64/glibc-hwcaps/.
# ---------------------------------------------------------------------------

(umask 077; echo 'libhardened_malloc-light.so libno_rlimit_as.so' > /etc/ld.so.preload)

# Set LD_PRELOAD for PAM sessions (greetd -> niri). Drop any stale entry first.
sed -i '/^LD_PRELOAD[[:space:]]*DEFAULT=/d' /etc/security/pam_env.conf
[ -n "$(tail -c1 /etc/security/pam_env.conf 2>/dev/null || echo)" ] && echo >> /etc/security/pam_env.conf
printf '%s\n' 'LD_PRELOAD DEFAULT="libhardened_malloc-light.so libno_rlimit_as.so"' >> /etc/security/pam_env.conf

# Mask GDM and enable greetd as the display-manager
systemctl mask gdm.service
systemctl enable greetd.service

# Disable COPRs so they don't end up enabled on the final image:
bash /ctx/install-repos.sh disable

kver="$(cd /usr/lib/modules && echo *)"
depmod -a "${kver}"
dracut -vf "/usr/lib/modules/${kver}/initramfs.img" "${kver}"

# Kernel module loads must be allowed by SELinux (can't allow at build-time
# because setsebool requires a loaded kernel, so a oneshot unit applies it
# at boot)
systemctl enable setsebool-domain-kernel-load-modules.service

systemctl enable tlp.service
systemctl enable zcfan.service
systemctl enable throttled.service
systemctl enable virtqemud.service
systemctl enable virtnetworkd.service
systemctl mask systemd-rfkill.service systemd-rfkill.socket

# ---------------------------------------------------------------------------
# CJK font support for Flatpak Firefox
# Flatpak's fontconfig inside the Freedesktop runtime doesn't properly scan
# /run/host/fonts/ for CJK fonts.  We add a per-user fonts.conf that
# explicitly tells fontconfig to scan the CJK font directory, which maps
# correctly inside the sandbox.  A systemd oneshot service distributes this
# to existing users at boot; new users get it via /etc/skel.
# ---------------------------------------------------------------------------

systemctl enable cjk-fonts-flatpak.service

# Populate /etc/skel so new users get the config
mkdir -p /etc/skel/.var/app/org.mozilla.firefox/config/fontconfig
cp /usr/share/cjk-fonts-flatpak/fonts.conf /etc/skel/.var/app/org.mozilla.firefox/config/fontconfig/fonts.conf

# Clean runtime-only directories that packages populate at install time
rm -rf /run/gluster

dnf5 -y remove dnf5-plugin-manifest libpkgmanifest createrepo_c
dnf5 clean all

rm -rf packages.manifest/ packages.manifest.yaml
