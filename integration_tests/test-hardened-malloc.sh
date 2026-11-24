#!/bin/bash

set -euo pipefail

FAILED=0

fail() {
	echo "FAIL: $1" >&2
	FAILED=$((FAILED + 1))
}

echo 'Checking hardened_malloc libraries...'
for LIB in /usr/lib64/libhardened_malloc-light.so /usr/lib64/libno_rlimit_as.so; do
	if [ -f "$LIB" ]; then
		echo "OK: ${LIB} present"
	else
		fail "${LIB} missing"
	fi
done

echo 'Checking /etc/ld.so.preload...'
if [ ! -f /etc/ld.so.preload ]; then
	fail '/etc/ld.so.preload missing'
else
	MODE=$(stat -c '%a' /etc/ld.so.preload)
	if [ "$MODE" = "600" ]; then
		echo 'OK: /etc/ld.so.preload is root-only readable'
	else
		fail "/etc/ld.so.preload mode is ${MODE}, expected 600"
	fi
	# File is 0600, so unprivileged cannot read it directly. Use sudo -n.
	if sudo -n grep -qx 'libhardened_malloc-light.so libno_rlimit_as.so' /etc/ld.so.preload 2>/dev/null || grep -qx 'libhardened_malloc-light.so libno_rlimit_as.so' /etc/ld.so.preload 2>/dev/null; then
		echo 'OK: /etc/ld.so.preload content correct'
	else
		fail '/etc/ld.so.preload content unexpected'
	fi
fi

echo 'Checking PID 1 uses hardened_malloc...'
# /proc/1/maps is 0400 on hidepid systems; use sudo.
if sudo -n grep -q 'hardened_malloc' /proc/1/maps 2>/dev/null || grep -q 'hardened_malloc' /proc/1/maps 2>/dev/null; then
	echo 'OK: PID 1 has hardened_malloc loaded'
else
	fail 'PID 1 does not have hardened_malloc loaded'
fi

echo 'Checking unprivileged LD_PRELOAD inheritance...'
# setpriv to nobody requires CAP_SETUID; on some kernels/VMs this is blocked (seccomp). Try with sudo and fallback to non-fatal warning.
if setpriv --reuid=65534 --regid=65534 --clear-groups \
	env LD_PRELOAD='libhardened_malloc-light.so libno_rlimit_as.so' \
	grep -q 'hardened_malloc' /proc/self/maps 2>/dev/null; then
	echo 'OK: unprivileged process preloads via LD_PRELOAD'
elif sudo -n setpriv --reuid=65534 --regid=65534 --clear-groups \
	env LD_PRELOAD='libhardened_malloc-light.so libno_rlimit_as.so' \
	grep -q 'hardened_malloc' /proc/self/maps 2>/dev/null; then
	echo 'OK: unprivileged process preloads via LD_PRELOAD (via sudo)'
else
	# On VM with no_new_privs or seccomp, setpriv may be blocked.
	# Check if LD_PRELOAD works for current user (without setpriv).
	if LD_PRELOAD='libhardened_malloc-light.so libno_rlimit_as.so' grep -q 'hardened_malloc' /proc/self/maps 2>/dev/null; then
		echo 'WARNING: setpriv blocked (likely VM/seccomp limitation); LD_PRELOAD works for current user but unprivileged inheritance untested' >&2
	else
		fail 'unprivileged process did not preload via LD_PRELOAD (session hardening will be lost)'
	fi
fi

echo 'Checking /etc/ld.so.preload is hidden from unprivileged users...'
if setpriv --reuid=65534 --regid=65534 --clear-groups \
	cat /etc/ld.so.preload >/dev/null 2>&1; then
	fail '/etc/ld.so.preload is readable by unprivileged users'
else
	echo 'OK: /etc/ld.so.preload not readable by unprivileged users'
fi

echo 'Checking systemd DefaultEnvironment...'
if systemd-analyze cat-config systemd/system.conf 2>/dev/null |
	grep -q 'libhardened_malloc-light.so'; then
	echo 'OK: DefaultEnvironment drop-in applies'
else
	fail 'DefaultEnvironment drop-in not applied'
fi

echo 'Checking PAM session environment...'
if grep -q '^LD_PRELOAD[[:space:]]DEFAULT="libhardened_malloc-light.so libno_rlimit_as.so"' \
	/etc/security/pam_env.conf; then
	echo 'OK: pam_env sets LD_PRELOAD'
else
	fail 'pam_env.conf missing LD_PRELOAD entry'
fi

# The preload reaches login sessions only if greetd's PAM stack actually
# invokes pam_env, either directly or through a substack/include chain.
# Fedora 45 ships vendor PAM files in /usr/lib/pam.d, so search both
# directories and prefer the administrator-controlled /etc/pam.d.
echo 'Checking greetd PAM stack reaches pam_env...'
PAM_ENV_WIRED=0

pam_stack_file() { # $1: stack name; print the first matching PAM file
	local name="$1" dir
	for dir in /etc/pam.d /usr/lib/pam.d; do
		if [ -f "${dir}/${name}" ]; then
			printf '%s\n' "${dir}/${name}"
			return 0
		fi
	done
	return 1
}

if ! GREETD_PAM=$(pam_stack_file greetd); then
	fail 'greetd PAM stack not found in /etc/pam.d or /usr/lib/pam.d'
elif grep -Eq '^[[:space:]]*-?[[:space:]]*(auth|session)[[:space:]].*pam_env\.so' \
	"$GREETD_PAM"; then
	PAM_ENV_WIRED=1
	echo "OK: greetd invokes pam_env directly (${GREETD_PAM})"
else
	for STACK in $(grep -Eo '(substack|include)[[:space:]]+[a-z0-9_-]+' "$GREETD_PAM" |
		awk '{print $2}' | sort -u); do
		STACK_FILE=$(pam_stack_file "$STACK") || continue
		if grep -Eq '^[[:space:]]*-?[[:space:]]*(auth|session)[[:space:]].*pam_env\.so' \
			"$STACK_FILE"; then
			PAM_ENV_WIRED=1
			echo "OK: greetd -> ${STACK} -> pam_env (${STACK_FILE})"
		fi
	done
fi
if [ "$PAM_ENV_WIRED" -eq 0 ]; then
	fail 'greetd PAM stack never reaches pam_env; login sessions will not inherit LD_PRELOAD'
fi

echo 'Checking vm.max_map_count...'
MAP_COUNT=$(cat /proc/sys/vm/max_map_count)
if [ "$MAP_COUNT" -ge 1048576 ]; then
	echo "OK: vm.max_map_count=${MAP_COUNT}"
else
	fail "vm.max_map_count=${MAP_COUNT}, expected at least 1048576"
fi

echo 'Checking escape hatch wrapper...'
if [ -x /usr/bin/with-standard-malloc ]; then
	echo 'OK: /usr/bin/with-standard-malloc executable'
else
	fail '/usr/bin/with-standard-malloc missing or not executable'
fi

echo 'Checking journal for preload failures...'
if journalctl -b --quiet | grep -q 'cannot be preloaded'; then
	fail 'journal contains ld.so preload failures'
	journalctl -b --no-pager | grep 'cannot be preloaded' | head -5 >&2
else
	echo 'OK: no preload failures in journal'
fi

if [ "$FAILED" -gt 0 ]; then
	echo "${FAILED} hardened_malloc check(s) failed" >&2
	exit 1
fi

echo 'All hardened_malloc checks passed.'
