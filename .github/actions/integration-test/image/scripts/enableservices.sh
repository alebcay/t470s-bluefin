#!/usr/bin/env bash

# Copyright 2025 The Secureblue Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

set -oue pipefail

# Enable/disable is handled by the preset file in
# /usr/lib/systemd/system-preset/99-integration-test.preset
# because BIB's osbuild pipeline regenerates /etc/systemd/system/
# symlinks and discards Containerfile-era systemctl enable calls.

systemctl unmask sshd.service || true
systemctl unmask sshd.socket || true

# sshd-unix-local.socket only exists at runtime so we can unmask it
# but cannot enable it at build-time.
systemctl unmask sshd-unix-local.socket || true  # unit only exists on some hardened bases

systemctl unmask sshd-keygen.target || true

# bootc-unified-storage is experimental and fails on images not installed with
# --experimental-unified-storage; mask it so it does not delay boot.
systemctl mask bootc-unified-storage.service || true

chmod 600 /etc/NetworkManager/system-connections/static.nmconnection
