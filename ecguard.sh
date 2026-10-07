#!/bin/bash
# ecguard v1.0: NUC X15 (LAPKC71F) 断电护栏守护 — 充电涌流守卫 + GPU 功率跌落观测
# 背景(2026-10-07 三案验尸):GPU 满载(120W+)释放后 15-25 秒 EC 硬切,签名稳定;
# 头号嫌疑 = 负载跌落时适配器腾出电流灌电池,充电路径异常即切。
# 护栏 = EC 充电档案切 STATIONARY(0x07A6 bits4-5=0x20,软件版"拔电池",完全可逆),
# 同时持续记录 GPU 功率跌落事件供判别(跌落照记,若不再断电即坐实充电通路说)。
# 用法: ecguard arm(武装,daemon 模式前台跑) | ecguard status | ecguard release(还原充电)
set -u
OEM4=0x07A6
LOG=/run/ecguard.state
GSTATE=/run/ecguard.gpu
HIGHCAP=0x00; BALANCED=0x10; STATIONARY=0x20

oem4_read() {
  sudo -n python3 - <<'PY' 2>/dev/null
import os, time
fd = os.open("/dev/ec", os.O_RDWR)
def rd(o):
    os.lseek(fd, o, 0); return os.read(fd, 1)[0]
def wr(o, v):
    os.lseek(fd, o, 0); os.write(fd, bytes([v]))
al, ah = 0xA6, 0x07
wr(0x8C, rd(0x8C) | 0x04); wr(0x8A, al); wr(0x8B, ah)
wr(0x8C, (rd(0x8C) & 0x7F) | 0x01)
for _ in range(30):
    time.sleep(0.015)
    if rd(0x8C) & 0x80: break
lo = rd(0x8D); wr(0x8C, 0)
print(lo)
PY
}

oem4_write() {  # $1 = profile bits (0x00/0x10/0x20)
  sudo -n python3 - "$1" <<'PY' 2>/dev/null
import os, sys, time
bits = int(sys.argv[1], 16)
fd = os.open("/dev/ec", os.O_RDWR)
def rd(o):
    os.lseek(fd, o, 0); return os.read(fd, 1)[0]
def wr(o, v):
    os.lseek(fd, o, 0); os.write(fd, bytes([v]))
def mb(data=None):
    wr(0x8C, rd(0x8C) | 0x04); wr(0x8A, 0xA6); wr(0x8B, 0x07)
    if data is None:
        wr(0x8C, (rd(0x8C) & 0x7F) | 0x01)
    else:
        wr(0x8D, data); wr(0x8E, 0)
        wr(0x8C, (rd(0x8C) & 0x7F) | 0x02)
    for _ in range(30):
        time.sleep(0.015)
        if rd(0x8C) & 0x80: break
    lo = rd(0x8D); wr(0x8C, 0)
    return lo
cur = mb()
mb((cur & ~0x30) | bits)
print(mb())
PY
}

gpu_w() { nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9.'; }

case "${1:-}" in
status)
  v=$(oem4_read); p=$(( (v & 0x30) >> 4 ))
  case $p in 2) prof=stationary;; 1) prof=balanced;; *) prof=high-cap;; esac
  echo "OEM_4=0x$(printf %02x "$v") profile=$prof"
  echo "battery: $(cat /sys/class/power_supply/BAT0/status 2>/dev/null) cur=$(cat /sys/class/power_supply/BAT0/current_now 2>/dev/null)uA"
  echo "guard: $( [ -f /run/ecguard.pid ] && echo running pid=$(cat /run/ecguard.pid) || echo stopped)"
  ;;
release)
  v=$(oem4_write "$BALANCED"); echo "released -> OEM_4=0x$(printf %02x $v) (balanced,恢复充电)"
  ;;
arm)
  v=$(oem4_write "$STATIONARY"); echo "armed -> OEM_4=0x$(printf %02x $v) (stationary,充电休眠)"
  echo $$ > /run/ecguard.pid
  prev=$(gpu_w); prev=${prev%.*}
  while :; do
    w=$(gpu_w); w=${w%.*}
    if [ -n "$w" ] && [ -n "$prev" ] && [ "$prev" -gt 0 ] 2>/dev/null; then
      d=$(( prev - w ))
      if [ "$d" -gt 60 ]; then
        echo "$(date '+%F %T') gpu-drop ${prev}W -> ${w}W (-${d}W) [guard:charge-asleep]" >> "$LOG"
      fi
    fi
    prev=$w
    printf "gpuW=%s %s\n" "$w" "$(date '+%F %T')" > "$GSTATE"
    sleep 2
  done
  ;;
*)
  echo "用法: ecguard arm|status|release" >&2; exit 1 ;;
esac
