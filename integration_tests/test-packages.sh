#!/bin/bash

set -euo pipefail

FAILED=0

fail() {
	echo "FAIL: $1" >&2
	FAILED=$((FAILED + 1))
}

parse_package_list() {
	awk '/^packages:/{flag=1; next} /^[[:alpha:]]/{flag=0} flag && $1 == "-" && NF >= 2 { print $2 }' "$1"
}

REQUIRED_INPUT="${HOME}/rpms.in.yaml"
REMOVALS_INPUT="${HOME}/rpms.remove.yaml"

for INPUT in "$REQUIRED_INPUT" "$REMOVALS_INPUT"; do
	if [ ! -f "$INPUT" ]; then
		echo "FAIL: ${INPUT} not found (build_files/*.yaml must be passed via data-files)" >&2
		exit 1
	fi
done

mapfile -t REQUIRED_PACKAGES < <(parse_package_list "$REQUIRED_INPUT")
if [ "${#REQUIRED_PACKAGES[@]}" -eq 0 ]; then
	echo "FAIL: parsed no packages from ${REQUIRED_INPUT}" >&2
	exit 1
fi

mapfile -t REMOVED_PACKAGES < <(parse_package_list "$REMOVALS_INPUT")
if [ "${#REMOVED_PACKAGES[@]}" -eq 0 ]; then
	echo "FAIL: parsed no packages from ${REMOVALS_INPUT}" >&2
	exit 1
fi

echo "Expecting ${#REQUIRED_PACKAGES[@]} package(s) installed and ${#REMOVED_PACKAGES[@]} package(s) absent."

echo 'Checking required packages...'
for PACKAGE in "${REQUIRED_PACKAGES[@]}"; do
	if rpm -q "$PACKAGE" >/dev/null 2>&1; then
		echo "OK: installed ${PACKAGE}"
	else
		fail "${PACKAGE} is not installed"
	fi
done

echo 'Checking removed packages...'
for PACKAGE in "${REMOVED_PACKAGES[@]}"; do
	if rpm -q "$PACKAGE" >/dev/null 2>&1; then
		fail "${PACKAGE} should have been removed but is installed"
	else
		echo "OK: absent ${PACKAGE}"
	fi
done

echo 'Checking binaries...'
for BINARY in niri greetd tlp zcfan throttled starship; do
	if command -v "$BINARY" >/dev/null 2>&1; then
		echo "OK: ${BINARY} on PATH"
	else
		fail "${BINARY} not found on PATH"
	fi
done

echo 'Checking bootc status...'
if sudo bootc status >/dev/null; then
	echo 'OK: bootc status succeeded'
else
	fail 'bootc status failed'
fi

echo 'Checking kernel arguments...'
if grep -q 'thinkpad_acpi.fan_control=1' /proc/cmdline; then
	echo 'OK: thinkpad_acpi.fan_control=1 present in cmdline'
else
	fail "thinkpad_acpi.fan_control=1 missing from /proc/cmdline ($(cat /proc/cmdline))"
fi

if [ "$FAILED" -gt 0 ]; then
	echo "${FAILED} package check(s) failed" >&2
	exit 1
fi

echo 'All package checks passed.'
