#!/bin/bash

set -euo pipefail

ENABLED_SERVICES=(
	greetd.service
	tlp.service
	zcfan.service
	throttled.service
	cjk-fonts-flatpak.service
	setsebool-domain-kernel-load-modules.service
)

ACTIVE_SERVICES=(
	greetd.service
	tlp.service
	throttled.service
)

ONESHOT_SERVICES=(
	cjk-fonts-flatpak.service
	setsebool-domain-kernel-load-modules.service
)

MASKED_UNITS=(
	gdm.service
	systemd-rfkill.service
	systemd-rfkill.socket
)

FAILED=0

fail() {
	echo "FAIL: $1" >&2
	FAILED=$((FAILED + 1))
}

echo 'Checking enabled services...'
for SERVICE in "${ENABLED_SERVICES[@]}"; do
	if STATE=$(systemctl is-enabled "$SERVICE" 2>&1); then
		echo "OK: ${STATE} ${SERVICE}"
	else
		fail "${SERVICE} is not enabled (state: ${STATE})"
	fi
done

echo 'Checking active services...'
for SERVICE in "${ACTIVE_SERVICES[@]}"; do
	if systemctl is-active --quiet "$SERVICE"; then
		echo "OK: active ${SERVICE}"
	else
		fail "${SERVICE} is not active (state: $(systemctl is-active "$SERVICE" 2>&1 || true))"
	fi
done

echo 'Checking oneshot services finished successfully...'
for SERVICE in "${ONESHOT_SERVICES[@]}"; do
	RESULT=$(systemctl show -p Result --value "$SERVICE")
	if [ "$RESULT" = "success" ]; then
		echo "OK: success ${SERVICE}"
	else
		fail "${SERVICE} did not finish successfully (Result: ${RESULT})"
	fi
done

echo 'Checking masked units...'
for UNIT in "${MASKED_UNITS[@]}"; do
	STATE=$(systemctl is-enabled "$UNIT" 2>/dev/null || true)
	if [ "$STATE" = "masked" ]; then
		echo "OK: masked ${UNIT}"
	else
		fail "${UNIT} is not masked (state: ${STATE:-unknown})"
	fi
done

if [ "$FAILED" -gt 0 ]; then
	echo "${FAILED} service check(s) failed" >&2
	exit 1
fi

echo 'All service checks passed.'
