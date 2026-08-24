#!/bin/bash

set -euo pipefail

REQUIRED_FILES=(
	/usr/lib/bootc/kargs.d/99-thinkpad-fan-control.toml
	/usr/lib/modprobe.d/t470s-i915.conf
	/usr/lib/dracut/dracut.conf.d/20-t470s-early-kms.conf
	/usr/lib/dracut/dracut.conf.d/20-t470s-bootc-ostree.conf
	/etc/greetd/config.toml
	/usr/share/factory/var/lib/noctalia-greeter/greeter.toml
	/usr/lib/tmpfiles.d/tlp.conf
	/usr/lib/tmpfiles.d/noctalia-greeter.conf
	/usr/lib/systemd/system/cjk-fonts-flatpak.service
	/usr/lib/systemd/system/setsebool-domain-kernel-load-modules.service
	/usr/share/cjk-fonts-flatpak/fonts.conf
	/etc/skel/.var/app/org.mozilla.firefox/config/fontconfig/fonts.conf
)

FAILED=0

fail() {
	echo "FAIL: $1" >&2
	FAILED=$((FAILED + 1))
}

echo 'Checking required files...'
for FILE in "${REQUIRED_FILES[@]}"; do
	if [ -f "$FILE" ]; then
		echo "OK: ${FILE}"
	else
		fail "${FILE} does not exist"
	fi
done

echo 'Checking file contents...'
if grep -q 'thinkpad_acpi.fan_control=1' /usr/lib/bootc/kargs.d/99-thinkpad-fan-control.toml; then
	echo 'OK: kargs definition contains fan_control'
else
	fail 'kargs definition missing thinkpad_acpi.fan_control=1'
fi

for OPTION in enable_guc=2 enable_psr=1 enable_rc6=7; do
	if grep -q "$OPTION" /usr/lib/modprobe.d/t470s-i915.conf; then
		echo "OK: i915 option ${OPTION}"
	else
		fail "i915 option ${OPTION} missing from t470s-i915.conf"
	fi
done

if grep -qi 'noctalia' /etc/greetd/config.toml; then
	echo 'OK: greetd is configured for noctalia-greeter'
else
	fail 'greetd config does not reference noctalia-greeter'
fi

if [ "$FAILED" -gt 0 ]; then
	echo "${FAILED} config check(s) failed" >&2
	exit 1
fi

echo 'All config checks passed.'
