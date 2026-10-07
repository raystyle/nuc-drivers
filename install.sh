#!/bin/bash
# nuc-fantool installer v2.3: acpi_ec + fanctl-omc 服务 + tuxedo 栈 + kbdlight ITE8291 直驱(Ubuntu 26.04 / kernel 7.0 实测)
set -euo pipefail
cd "$(dirname "$0")"

echo "== deps"
sudo apt-get update -qq || true
sudo apt-get install -y "linux-headers-$(uname -r)" build-essential git

KVER=$(uname -r)

echo "== tuxedo 栈在位检查(键盘背光依赖,0.3.9 预装于本机型镜像)"
if ! find /lib/modules/$KVER -name 'tuxedo_keyboard.ko*' | grep -q .; then
  echo "   警告: 未找到 tuxedo_keyboard 模块;键盘背光与 kbdlight 不可用,风扇服务不受影响" >&2
fi

echo "== acpi_ec module"
TMP=$(mktemp -d)
git clone -q https://github.com/musikid/acpi_ec "$TMP/acpi_ec"
make -C "$TMP/acpi_ec/src" >/dev/null
sudo install -D -m 644 "$TMP/acpi_ec/src/acpi_ec.ko" "/lib/modules/$KVER/extra/acpi_ec.ko"
sudo depmod -a
echo acpi_ec | sudo tee /etc/modules-load.d/acpi_ec.conf >/dev/null
sudo modprobe acpi_ec
test -e /dev/ec

echo "== 键盘背光栈: blacklist 主线 uniwill_laptop + 强制 tuxedo uw type 1"
sudo install -D -m 644 conf/modprobe-tuxedo-uniwill.conf /etc/modprobe.d/tuxedo-uniwill.conf
echo uniwill_wmi | sudo tee /etc/modules-load.d/tuxedo-drivers.conf >/dev/null
echo "   (blacklist 下次启动生效;当前会话如主线 uniwill_laptop 在载,可手动切换:"
echo "     sudo modprobe -r uniwill_laptop tuxedo_nb02_nvidia_power_ctrl 2>/dev/null; sudo modprobe tuxedo_keyboard)"

echo "== fanctl service"
sudo install -m 755 fanctl-omc.sh /usr/local/bin/fanctl-omc.sh
sudo install -m 644 fanctl-omc.service /etc/systemd/system/fanctl-omc.service
sudo systemctl daemon-reload
sudo systemctl enable --now fanctl-omc

echo "== kbdlight 键盘背光旋钮 + 开机默认白光"
sudo install -m 755 kbdlight /usr/local/bin/kbdlight
sudo install -m 644 kbdlight-default.service /etc/systemd/system/kbdlight-default.service
sudo systemctl daemon-reload
sudo systemctl enable kbdlight-default >/dev/null 2>&1 || true

echo "== gnome shell extension(注销重登一次后生效)"
EXTDIR="$HOME/.local/share/gnome-shell/extensions/fantool@nuc-fantool"
mkdir -p "$EXTDIR"
cp gnome-extension/fantool@nuc-fantool/* "$EXTDIR"/
gnome-extensions enable fantool@nuc-fantool 2>/dev/null || echo "   (当前会话未识别,注销重登后自动启用)"

sleep 3
systemctl is-active fanctl-omc && echo "== installed: fanctl-omc active(温度曲线默认 60/70/80 起 2500/3500/5000)"
