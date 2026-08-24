# vim: set ft=make :

# Give Flatpak apps access to host hardened_malloc (light variant).
# Works globally without an argument, or for one app: ujust harden-flatpak APP_ID
[group('Flatpak')]
harden-flatpak app_id="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Pick the best microarchitecture build present on the host.
    # Absolute LD_PRELOAD paths bypass glibc-hwcaps auto-selection,
    # so we detect the highest available x86-64-vN variant that has the library.
    uarch=""
    for v in 4 3 2; do
        if [ -f "/usr/lib64/glibc-hwcaps/x86-64-v${v}/libhardened_malloc-light.so" ]; then
            uarch="${v}"
            break
        fi
    done

    malloc_path="/var/run/host/usr/lib64/libhardened_malloc-light.so"
    if [ -n "${uarch}" ]; then
        malloc_path="/var/run/host/usr/lib64/glibc-hwcaps/x86-64-v${uarch}/libhardened_malloc-light.so"
    fi
    preload="${malloc_path} /var/run/host/usr/lib64/libno_rlimit_as.so"

    scope_args=()
    target="all Flatpak apps"
    if [ -n "{{ app_id }}" ]; then
        scope_args=("{{ app_id }}")
        target="{{ app_id }}"
    fi

    flatpak override --user \
        --filesystem=host-os:ro \
        --env=LD_PRELOAD="${preload}" \
        "${scope_args[@]}"
    echo "Enabled hardened_malloc for ${target}"

# Remove the hardened_malloc overrides made by harden-flatpak.
# Works globally without an argument, or for one app: ujust unharden-flatpak APP_ID
[group('Flatpak')]
unharden-flatpak app_id="":
    #!/usr/bin/env bash
    set -euo pipefail

    scope_args=()
    target="all Flatpak apps"
    if [ -n "{{ app_id }}" ]; then
        scope_args=("{{ app_id }}")
        target="{{ app_id }}"
    fi

    flatpak override --user \
        --unset-env=LD_PRELOAD \
        --nofilesystem=host-os \
        "${scope_args[@]}"
    echo "Disabled hardened_malloc for ${target}"
