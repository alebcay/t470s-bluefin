#!/bin/bash
set -ouex pipefail

COPR="bieszczaders/kernel-cachyos-lto"
PKG="kernel-cachyos-lto"

dnf5 -y copr enable "$COPR"

case "${1:-}" in
  query-version)
    KVER=$(dnf5 repoquery --latest-limit 1 \
      --queryformat '%{VERSION}-%{RELEASE}' \
      "$PKG" 2>/dev/null)
    if [ -z "$KVER" ]; then
      KVER=$(dnf5 list available "$PKG" 2>/dev/null \
        | awk '/^kernel-cachyos/{print $2; exit}')
    fi
    echo "$KVER"
    ;;
  build)
    dnf5 -y install rpm-build bc bison dwarves elfutils-devel flex \
      gettext-devel kmod make openssl openssl-devel perl-Carp perl-devel \
      perl-generators perl-interpreter python3-devel python3-pyyaml \
      python-srpm-macros clang lld llvm

    dnf5 download --source "$PKG"
    _srpm="$(ls "$PKG"-*.src.rpm)"
    _srpm_path="$PWD/$_srpm"
    rm -rf /var/tmp/rpmbuild
    mkdir -p /var/tmp/rpmbuild/{SOURCES,SPECS,RPMS,SRPMS,BUILD}
    cd /var/tmp/rpmbuild
    rpm2cpio "$_srpm_path" | cpio -imv
    mv "$PKG".spec SPECS/
    for f in *; do [ -f "$f" ] && mv "$f" SOURCES/; done
    cd /
    sed -i '/CACHY -e SCHED_BORE/a scripts/config -e COMPOSEFS -e EROFS_FS -e OVERLAY_FS' \
      /var/tmp/rpmbuild/SPECS/"$PKG".spec

    rpmbuild --define "_topdir /var/tmp/rpmbuild" -ba /var/tmp/rpmbuild/SPECS/"$PKG".spec

    mkdir -p /tmp/kernel-rpms
    cp /var/tmp/rpmbuild/RPMS/x86_64/*.rpm /tmp/kernel-rpms/
    ;;
  *)
    echo "Usage: $0 {query-version|build}" >&2
    exit 1
    ;;
esac
