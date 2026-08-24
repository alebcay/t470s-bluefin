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
	# Wait out the transient 'activating' window before judging the state.
	STATE=""
	for _ in {1..30}; do
		STATE=$(systemctl is-active "$SERVICE" 2>&1 || true)
		[ "$STATE" = "activating" ] || break
		sleep 2
	done

	if [ "$STATE" = "active" ]; then
		echo "OK: active ${SERVICE}"
		continue
	fi

	# throttled requires Intel hardware; in QEMU VM it will fail. Don't hard-fail in virtualized environment.
	if [ "$SERVICE" = "throttled.service" ] && systemd-detect-virt --quiet 2>/dev/null; then
		echo "WARN: ${SERVICE} is not active (state: ${STATE}) but running in VM, skipping" >&2
		continue
	fi

	# greetd is a graphical display manager. In a headless VM (--graphics=none,
	# no seat) the greeter has no display to attach to, so greetd can stay in
	# 'activating' indefinitely. Only a terminal failure is a real problem here.
	if [ "$SERVICE" = "greetd.service" ] && systemd-detect-virt --quiet 2>/dev/null; then
		case "$STATE" in
			activating | reloading)
				echo "OK: ${STATE} ${SERVICE} (headless VM, greeter has no display)"
				;;
			*)
				fail "${SERVICE} is not active (state: ${STATE})"
				;;
		esac
		continue
	fi

	fail "${SERVICE} is not active (state: ${STATE})"
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
