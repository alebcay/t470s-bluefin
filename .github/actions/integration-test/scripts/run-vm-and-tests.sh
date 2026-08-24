#!/usr/bin/env bash
# Start a VM from the BIB disk, wait for SSH, and run the integration tests.
# Designed for both GitHub Actions and local use.
#
# Required env:
#   TESTS      - newline-separated list of test script paths
# Optional env:
#   DATA_FILES - newline-separated list of data files to copy
#   VM_NAME    - libvirt domain name (default: vm-bootc)
#   VCPUS      - vCPU count (default: 3)
#   MEMORY_MB  - RAM in MB (default: 8192)
#   DISK_SIZE_GB - disk size in GB (default: 30)
#   STARTUP_WAIT_SECONDS - sleep after virt-install (default: 0)
#   VM_IP      - guest IP (default: 192.168.122.2)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${TESTS:?TESTS is required}"

VM_NAME="${VM_NAME:-vm-bootc}"
VCPUS="${VCPUS:-3}"
MEMORY_MB="${MEMORY_MB:-8192}"
DISK_SIZE_GB="${DISK_SIZE_GB:-30}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-0}"
VM_IP="${VM_IP:-192.168.122.2}"
DATA_FILES="${DATA_FILES:-}"

require_cmd virt-install
require_cmd nc
require_cmd scp
require_cmd ssh

DISK_IMAGE_PATH="/var/lib/libvirt/images/disk.qcow2"
if [[ ! -f "${DISK_IMAGE_PATH}" ]]; then
    die "disk not found at ${DISK_IMAGE_PATH} (run create-vm-disk.sh first)"
fi

mkdir -p test-logs
BOOT_LOG_PATH="$(realpath test-logs)/boot.log"

log_section "Starting VM ${VM_NAME}"
sudo virt-install \
    --connect="qemu:///system" \
    --name="${VM_NAME}" \
    --vcpus="${VCPUS}" \
    --memory="${MEMORY_MB}" \
    --import \
    --graphics=none \
    --os-variant="silverblue-unknown" \
    --disk="size=${DISK_SIZE_GB},backing_store=${DISK_IMAGE_PATH}" \
    --serial="file,path=${BOOT_LOG_PATH}" \
    --network network=default \
    --noautoconsole

if [[ "${STARTUP_WAIT_SECONDS}" -gt 0 ]]; then
    echo "Waiting ${STARTUP_WAIT_SECONDS}s for VM to start..."
    sleep "${STARTUP_WAIT_SECONDS}"
fi

readarray -t TEST_LIST < <(printf '%s\n' "${TESTS}" | sed '/^[[:space:]]*$/d')
readarray -t DATA_FILE_LIST < <(printf '%s\n' "${DATA_FILES}" | sed '/^[[:space:]]*$/d')

log_section "Waiting for SSH on ${VM_IP}:22"
for i in {1..30}; do
    if nc -z "${VM_IP}" 22; then
        break
    elif (( i == 30 )); then
        die "SSH port on ${VM_IP} is not open after 30 attempts"
    fi
    sleep 5
done
echo "SSH port is open on ${VM_IP}."
# Give sshd a moment to recover from MaxStartups probes.
sleep 10

SSH_OPTS=(-o ConnectTimeout=20 -o StrictHostKeyChecking=no -i "${HOME}/.ssh/id_ed25519")

log_section "Copying tests and data to VM"
for attempt in {1..5}; do
    echo "scp attempt ${attempt}"
    if scp -v "${SSH_OPTS[@]}" "${TEST_LIST[@]}" "${DATA_FILE_LIST[@]}" "core@${VM_IP}:/home/core/" 2>&1 | tee /tmp/scp-attempt.log; then
        echo "scp succeeded on attempt ${attempt}"
        break
    fi
    echo "scp attempt ${attempt} failed"
    cat /tmp/scp-attempt.log | tail -20 || true
    sleep 5
    if (( attempt == 5 )); then
        die "scp failed after 5 attempts"
    fi
done

FAILED_TESTS=0
for TEST_FILE in "${TEST_LIST[@]}"; do
    echo "Running test: ${TEST_FILE}"
    BASENAME="${TEST_FILE##*/}"
    REMOTE_PATH="/home/core/${BASENAME}"
    LOG_FILE="test-logs/${BASENAME}.log"

    set +e
    ssh "${SSH_OPTS[@]}" "core@${VM_IP}" "chmod +x ${REMOTE_PATH} && ${REMOTE_PATH}" 2>&1 | tee "${LOG_FILE}"
    TEST_EXIT_CODE=${PIPESTATUS[0]}
    set -e

    if (( TEST_EXIT_CODE != 0 )); then
        echo "::error::Test ${TEST_FILE} failed — see test-logs/${BASENAME}.log"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    sleep 1
done

if (( FAILED_TESTS > 0 )); then
    echo "${FAILED_TESTS} test(s) failed"
    exit 1
fi

echo "All tests passed"
