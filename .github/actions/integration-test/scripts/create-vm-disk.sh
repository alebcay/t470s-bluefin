#!/usr/bin/env bash
# Create a VM disk image from the integration test container via bootc-image-builder.
#
# Required env:
#   INTEGRATION_TEST_IMAGE - full image ref (e.g. ghcr.io/...:integrationtest-uuid)
# Optional env:
#   DISK_SIZE_GB   - not used here, but kept for compatibility
#   CONFIG_TOML    - path to config.toml template (default: ../config.toml next to this script)
#   OUTPUT_DIR     - output directory (default: ./output)
#   PUBKEY_FILE    - path to SSH pubkey (default: $HOME/.ssh/id_ed25519.pub)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${INTEGRATION_TEST_IMAGE:?INTEGRATION_TEST_IMAGE is required}"

CONFIG_TOML="${CONFIG_TOML:-${SCRIPT_DIR}/../config.toml}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
PUBKEY_FILE="${PUBKEY_FILE:-${HOME}/.ssh/id_ed25519.pub}"

require_cmd podman

if [[ ! -f "${PUBKEY_FILE}" ]]; then
    die "pubkey not found at ${PUBKEY_FILE}"
fi
if [[ ! -f "${CONFIG_TOML}" ]]; then
    die "config.toml not found at ${CONFIG_TOML}"
fi

PUBKEY="$(cat "${PUBKEY_FILE}")"
WORK_CONFIG="$(mktemp)"
cp "${CONFIG_TOML}" "${WORK_CONFIG}"
# shellcheck disable=SC2016
sed -i -e "s|%%PUBKEY%%|${PUBKEY}|g" "${WORK_CONFIG}"

mkdir -p "${OUTPUT_DIR}"
# Pull ensures the image is in the expected store (rootful podman for BIB).
sudo podman pull "${INTEGRATION_TEST_IMAGE}" >/dev/null

sudo podman run \
    --rm \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${OUTPUT_DIR}:/output" \
    -v "${WORK_CONFIG}:/config.toml:ro" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type qcow2 \
    --use-librepo=True \
    --rootfs btrfs \
    --progress verbose \
    "${INTEGRATION_TEST_IMAGE}"

sudo mv "${OUTPUT_DIR}/qcow2/disk.qcow2" /var/lib/libvirt/images/disk.qcow2
rm -f "${WORK_CONFIG}"

echo "Disk created at /var/lib/libvirt/images/disk.qcow2"
