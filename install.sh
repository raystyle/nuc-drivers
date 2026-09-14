#!/bin/bash
# nuc-fantool installer: acpi_ec module + fanctl-omc service (Ubuntu 26.04 / kernel 7.0 实测)
set -euo pipefail
cd "$(dirname "$0")"

echo "== deps"
sudo apt-get update -qq || true
sudo apt-get install -y "linux-headers-$(uname -r)" build-essential git

TMP=$(mktemp -d)
echo "== acpi_ec module"
git clone -q https://github.com/musikid/acpi_ec "$TMP/acpi_ec"
make -C "$TMP/acpi_ec/src" >/dev/null
KVER=$(uname -r)
sudo install -D -m 644 "$TMP/acpi_ec/src/acpi_ec.ko" "/lib/modules/$KVER/extra/acpi_ec.ko"
sudo depmod -a
echo acpi_ec | sudo tee /etc/modules-load.d/acpi_ec.conf >/dev/null
sudo modprobe acpi_ec
test -e /dev/ec

echo "== fanctl service"
sudo install -m 755 fanctl-omc.sh /usr/local/bin/fanctl-omc.sh
sudo install -m 644 fanctl-omc.service /etc/systemd/system/fanctl-omc.service
sudo systemctl daemon-reload
sudo systemctl enable --now fanctl-omc

echo "== gnome shell extension(注销重登一次后生效)"
EXTDIR="$HOME/.local/share/gnome-shell/extensions/fantool@nuc-fantool"
mkdir -p "$EXTDIR"
cp gnome-extension/fantool@nuc-fantool/* "$EXTDIR"/
gnome-extensions enable fantool@nuc-fantool 2>/dev/null || echo "   (当前会话未识别,注销重登后自动启用)"

sleep 3
systemctl is-active fanctl-omc && echo "== installed: fanctl-omc active(温度曲线默认 60/70/80 起 2500/3500/5000)"
