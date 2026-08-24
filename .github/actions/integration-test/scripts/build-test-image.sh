#!/usr/bin/env bash
# Build and push the thin integration test image that stacks onto the base
# image. Also usable outside GitHub Actions via local podman.
#
# Required env:
#   REGISTRY   - e.g. ghcr.io/alebcay
#   IMAGE      - e.g. t470s-bluefin-pr51
#   AUTH_FILE  - path to podman auth file (CI) or empty for local
# Optional env:
#   BASE_IMAGE - base image ref (default: ${REGISTRY}/${IMAGE}:latest)
#   TAG        - tag for the test image (default: integrationtest-<uuid>)
#   ACTION_IMAGE_DIR - directory containing Containerfile.in (default: image/ next to this script)
# Outputs:
#   Writes INTEGRATION_TEST_IMAGE to $GITHUB_ENV if present, else prints it.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${REGISTRY:?REGISTRY is required}"
: "${IMAGE:?IMAGE is required}"

AUTH_FILE="${AUTH_FILE:-}"
BASE_IMAGE="${BASE_IMAGE:-${REGISTRY}/${IMAGE}:latest}"
ACTION_IMAGE_DIR="${ACTION_IMAGE_DIR:-${SCRIPT_DIR}/../image}"
TAG="${TAG:-integrationtest-$(cat /proc/sys/kernel/random/uuid)}"

require_cmd podman

if [[ ! -f "${ACTION_IMAGE_DIR}/Containerfile.in" ]]; then
    die "Containerfile.in not found at ${ACTION_IMAGE_DIR}/Containerfile.in"
fi
if [[ ! -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
    die "SSH public key not found at ${HOME}/.ssh/id_ed25519.pub (run Generate SSH Keypair first)"
fi

IMAGE_REF="${REGISTRY}/${IMAGE}"
TMP_CONTAINERFILE="$(mktemp)"

cp "${HOME}/.ssh/id_ed25519.pub" "${ACTION_IMAGE_DIR}/authorized_keys"
sed -e "s|%%BASE_IMAGE%%|${BASE_IMAGE}|" \
    "${ACTION_IMAGE_DIR}/Containerfile.in" > "${TMP_CONTAINERFILE}"

BUILD_ARGS=()
if [[ -n "${AUTH_FILE}" ]]; then
    BUILD_ARGS+=(--authfile "${AUTH_FILE}")
fi

podman build \
    "${BUILD_ARGS[@]}" \
    -f "${TMP_CONTAINERFILE}" \
    -t "${IMAGE_REF}:${TAG}" \
    "${ACTION_IMAGE_DIR}"

if [[ -n "${AUTH_FILE}" ]]; then
    podman push --authfile "${AUTH_FILE}" "${IMAGE_REF}:${TAG}"
fi

INTEGRATION_TEST_IMAGE="${IMAGE_REF}:${TAG}"
echo "Built ${INTEGRATION_TEST_IMAGE}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "INTEGRATION_TEST_IMAGE=${INTEGRATION_TEST_IMAGE}" >> "${GITHUB_ENV}"
else
    echo "INTEGRATION_TEST_IMAGE=${INTEGRATION_TEST_IMAGE}"
fi

rm -f "${TMP_CONTAINERFILE}"
