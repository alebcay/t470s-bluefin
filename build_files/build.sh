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

# Strip GNOME desktop to the minimum — we use niri + Noctalia + greetd/noctalia-greeter
dnf5 -y remove \
  gdm gnome-shell gnome-session \
  gnome-control-center gnome-software gnome-software-fedora-latex \
  gnome-console gnome-terminal \
  nautilus \
  gnome-initial-setup gnome-tour gnome-user-docs \
  gnome-logs gnome-calendar gnome-contacts gnome-maps gnome-weather \
  gnome-clocks gnome-characters \
  gnome-calculator gnome-font-viewer \
  totem evince eog simple-scan baobab loupe snapshot epiphany \
  gnome-connections \
  gnome-shell-extension-apps-menu gnome-shell-extension-background-logo \
  gnome-shell-extension-launch-new-instance gnome-shell-extension-places \
  gnome-shell-extension-window-list gnome-shell-extension-workspace-indicator \
  gnome-browser-connector orca \
  tracker tracker-miners \
  rygel sushi \
  xdg-desktop-portal-gnome

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

# Configure xdg-desktop-portal backends for niri
mkdir -p /etc/xdg-desktop-portal
cat > /etc/xdg-desktop-portal/niri-portals.conf << 'PORTCONF'
[preferred]
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
PORTCONF

# Set up greetd + noctalia-greeter (replaces GDM as display manager)

# Greeter runtime directory
mkdir -p /var/lib/noctalia-greeter
chmod 0755 /var/lib/noctalia-greeter

# greetd config
cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
command = "/usr/bin/noctalia-greeter-session"
user = "greetd"
EOF

# Skeleton greeter preferences
cat > /var/lib/noctalia-greeter/greeter.toml << 'EOF'
# noctalia-greeter greeter.toml
# [session] default/last, [user] default, [appearance] scheme/password_style
# [output] name/layout/scale, [cursor] theme/size/path, [keyboard] layout/variant/options
EOF
chown -R greetd:greetd /var/lib/noctalia-greeter 2>/dev/null || true

# Mask GDM and enable greetd as the display-manager
systemctl mask gdm.service
systemctl enable greetd.service

# Disable COPRs so they don't end up enabled on the final image:
dnf5 -y copr disable abn/throttled
dnf5 -y copr disable sneexy/python-validity
dnf5 -y copr disable lionheartp/Hyprland

# Ensure initramfs includes bootc and ostree modules for proper root filesystem setup
printf 'export DRACUT_NO_XATTR=1\nreproducible=yes\nadd_dracutmodules+=" bootc ostree "\n' | tee /usr/lib/dracut/dracut.conf.d/20-t470s-bootc-ostree.conf

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
