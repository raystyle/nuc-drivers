#!/bin/bash
# kbdlight v2.2: NUC X15 (LAPKC71F) 键盘背光旋钮
# 依赖 tuxedo_keyboard(uw_force_kbd_type=1,见 conf/modprobe-tuxedo-uniwill.conf),
# 两级定色白光:0 灭 / 1 低 / 2 高(sysfs 钳制,越界值落边界档)
# 用法: kbdlight          查当前档
#       kbdlight 0|1|2    设档
#       kbdlight +1|-1    相对调档
NODE=/sys/devices/platform/tuxedo_keyboard/leds/white:kbd_backlight
[ -e "$NODE/brightness" ] || { echo "kbdlight: no kbd backlight node(tuxedo_keyboard 未载?)" >&2; exit 1; }
MAX=$(cat "$NODE/max_brightness")
cur=$(cat "$NODE/brightness")
op=${1:-}
if [ -z "$op" ]; then
  echo "$cur / $MAX"
elif [ "$op" = "+1" ] || [ "$op" = "-1" ]; then
  v=$(( cur + op )); [ $v -lt 0 ] && v=0; [ $v -gt $MAX ] && v=$MAX
  echo "$v" | sudo tee "$NODE/brightness" >/dev/null && echo "$cur -> $v"
else
  case $op in *[!0-9]*) echo "kbdlight: 非法档值 $op(0-$MAX 或 +1/-1)" >&2; exit 1;; esac
  v=$op; [ $v -gt $MAX ] && v=$MAX
  echo "$v" | sudo tee "$NODE/brightness" >/dev/null && echo "$cur -> $v"
fi
