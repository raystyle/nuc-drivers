#!/bin/bash
# ecguard v2.1: NUC X15 (LAPKC71F) 断电护栏守护 — 三层
#   1. 充电涌流守卫:EC 充电档案 STATIONARY(0x07A6 bits4-5,可逆;v1 实战:纯 GPU
#      满载释放三轮五发 -60~74W 跌落零断电,但合成腿证明其非充分,故升 v2)
#   2. 总功率总督:CPU 占用 × PL + GPU power.draw 估总 draw,超预算压 GPU cTGP
#      (0x0744 偏移递减),回落后阶梯放行(滞回 15W)——治条件 A(CPU+GPU 并发
#      ~195W+ 即 EC 过载硬切,案 1/3/4;断前 ACPI workqueue 窒息告警为证)
#   3. 跌落观测:GPU 跌落 >60W 记录(/run/ecguard.state)
# 用法: ecguard arm(daemon) | status | release(恢复充电)
# 环境变量: ECGUARD_BUDGET(总功率预算瓦数,默认 165)
set -u
OEM4=0x07A6
CTGP_OFF=0x0744
LOG=/var/log/ecguard.log
GSTATE=/run/ecguard.gpu
BALANCED=0x10; STATIONARY=0x20
BUDGET=${ECGUARD_BUDGET:-140}
BASE=25            # 系统本体估耗(屏/内存/外设)
HYST=15            # 放行滞回

ec_rw() {  # $1=addr16hex $2=值(hex/dec) 或空=读;stdout=读回值
  sudo -n python3 - "$1" "${2:-}" <<'PY' 2>/dev/null
import os, sys, time
addr = int(sys.argv[1], 16)
data = int(sys.argv[2], 0) if len(sys.argv) > 2 and sys.argv[2] != "" else None
import fcntl
_lk = open("/run/ecmail.lock", "w")
fcntl.flock(_lk, fcntl.LOCK_EX)  # 邮箱跨进程串行
fd = os.open("/dev/ec", os.O_RDWR)
def rd(o):
    os.lseek(fd, o, 0); return os.read(fd, 1)[0]
def wr(o, v):
    os.lseek(fd, o, 0); os.write(fd, bytes([v]))
al, ah = addr & 0xff, (addr >> 8) & 0xff
wr(0x8C, rd(0x8C) | 0x04); wr(0x8A, al); wr(0x8B, ah)
if data is None:
    wr(0x8C, (rd(0x8C) & 0x7F) | 0x01)
else:
    wr(0x8D, data); wr(0x8E, 0)
    wr(0x8C, (rd(0x8C) & 0x7F) | 0x02)
for _ in range(30):
    time.sleep(0.015)
    if rd(0x8C) & 0x80: break
lo = rd(0x8D); wr(0x8C, 0)
fcntl.flock(_lk, fcntl.LOCK_UN)
print(lo)
PY
}

ec_write_bits() {  # $1=addr $2=byte
  sudo -n python3 - "$1" "$2" <<'PY' 2>/dev/null
import os, sys, time
addr, byte = int(sys.argv[1], 16), int(sys.argv[2], 0)
import fcntl
_lk = open("/run/ecmail.lock", "w")
fcntl.flock(_lk, fcntl.LOCK_EX)  # 邮箱跨进程串行
fd = os.open("/dev/ec", os.O_RDWR)
def rd(o):
    os.lseek(fd, o, 0); return os.read(fd, 1)[0]
def wr(o, v):
    os.lseek(fd, o, 0); os.write(fd, bytes([v]))
def mb(data=None):
    al, ah = addr & 0xff, (addr >> 8) & 0xff
    wr(0x8C, rd(0x8C) | 0x04); wr(0x8A, al); wr(0x8B, ah)
    if data is None: wr(0x8C, (rd(0x8C) & 0x7F) | 0x01)
    else:
        wr(0x8D, data); wr(0x8E, 0); wr(0x8C, (rd(0x8C) & 0x7F) | 0x02)
    for _ in range(30):
        time.sleep(0.015)
        if rd(0x8C) & 0x80: break
    lo = rd(0x8D); wr(0x8C, 0)
    return lo
mb(byte)
r = mb()
fcntl.flock(_lk, fcntl.LOCK_UN)
print(r)
PY
}

gpu_w() { nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9.'; }
pl1_w() { echo $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || echo 0) / 1000000 )); }

# CPU 占用%(/proc/stat 采样差)
cpu_prev=( $(sed -n 's/^cpu \(.*\)/\1/p' /proc/stat) )
cpu_util() {
  local cur=( $(sed -n 's/^cpu \(.*\)/\1/p' /proc/stat) )
  local idle=$(( cur[3] + cur[4] - cpu_prev[3] - cpu_prev[4] ))
  local total=0 i
  for i in "${!cur[@]}"; do total=$(( total + cur[i] - cpu_prev[i] )); done
  cpu_prev=( "${cur[@]}" )
  [ "$total" -gt 0 ] && echo $(( 100 * (total - idle) / total )) || echo 0
}

preset_gpu_off() {  # perfmode 预设 -> 期望 cTGP 偏移(用户意图上限)
  case "$(cat /run/perfmode.state 2>/dev/null | awk '{print $1}')" in
    performance-max) echo 45;; performance) echo 25;; balanced) echo 10;; battery-saver) echo 0;; *) echo 10;;
  esac
}

case "${1:-}" in
status)
  v=$(ec_rw "$OEM4"); p=$(( (v & 0x30) >> 4 ))
  case $p in 2) prof=stationary;; 1) prof=balanced;; *) prof=high-cap;; esac
  echo "OEM_4=0x$(printf %02x "$v") profile=$prof | budget=${BUDGET}W"
  echo "battery: $(cat /sys/class/power_supply/BAT0/status 2>/dev/null) cur=$(cat /sys/class/power_supply/BAT0/current_now 2>/dev/null)uA"
  echo "cTGP offset now: $(ec_rw "$CTGP_OFF") (preset wants $(preset_gpu_off))"
  echo "guard: $( [ -f /run/ecguard.pid ] && echo running pid=$(cat /run/ecguard.pid) || echo stopped)"
  ;;
release)
  v=$(ec_write_bits "$OEM4" "$BALANCED"); echo "released -> OEM_4=0x$(printf %02x "$v") (balanced,恢复充电)"
  ;;
arm)
  v=$(ec_write_bits "$OEM4" "$STATIONARY"); echo "armed -> OEM_4=0x$(printf %02x "$v") (stationary)"
  echo $$ > /run/ecguard.pid
  # cTGP 冷启动初始化(幂等;perfmode 未跑过也能独立工作,DB 基线关)
  ctrl=$(ec_rw 0x0743)
  if [ "${ctrl:-0}" -lt 5 ]; then
    ec_rw 0x0745 255 >/dev/null; ec_rw 0x0746 0 >/dev/null; ec_rw 0x0743 5 >/dev/null
    echo "$(date '+%F %T') ctgp cold-init (ctrl 0x$(printf %02x "${ctrl:-0}") -> 0x05, db=0)" >> "$LOG"
  fi
  cur_off=$(ec_rw "$CTGP_OFF"); cur_off=$(( ${cur_off:-0} ))
  prev_gpu=$(gpu_w); prev_gpu=${prev_gpu%.*}
  while :; do
    w=$(gpu_w); w=${w%.*}
    # 跌落观测
    if [ -n "$w" ] && [ -n "$prev_gpu" ] && [ "$prev_gpu" -gt 0 ] 2>/dev/null; then
      d=$(( prev_gpu - w ))
      [ "$d" -gt 60 ] && echo "$(date '+%F %T') gpu-drop ${prev_gpu}W -> ${w}W (-${d}W)" >> "$LOG"
    fi
    prev_gpu=$w
    # 总功率总督
    if [ -n "$w" ]; then
      u=$(cpu_util); pl=$(pl1_w)
      cpu_est=$(( pl * u / 100 ))
      total=$(( w + cpu_est + BASE ))
      want=$(preset_gpu_off)
      if [ "$total" -gt $(( BUDGET + 20 )) ] || { [ "$u" -gt 65 ] && [ "$w" -gt 50 ]; }; then
        # v2.1 预判钳压:合成形态(cpu 忙 + GPU 起势)或超预算 20W -> 一步到地板(赛跑必须赢在 t=0)
        if [ "$cur_off" -gt 0 ]; then
          ec_rw "$CTGP_OFF" 0 >/dev/null
          echo "$(date '+%F %T') FLOOR-CLAMP total=${total}W cpu${u}% gpu${w}W cTGP ${cur_off}->0" >> "$LOG"
          cur_off=0
        fi
      elif [ "$total" -gt "$BUDGET" ]; then
        new_off=$(( cur_off - 10 )); [ "$new_off" -lt 0 ] && new_off=0
        if [ "$new_off" -lt "$cur_off" ]; then
          ec_rw "$CTGP_OFF" "$new_off" >/dev/null
          echo "$(date '+%F %T') clamp total=${total}W(cpu${cpu_est}+gpu${w}+base${BASE}) cTGP ${cur_off}->${new_off}" >> "$LOG"
          cur_off=$new_off
        fi
      elif [ "$total" -lt $(( BUDGET - HYST )) ] && [ "$cur_off" -lt "$want" ] && ! { [ "$u" -gt 60 ] && [ "$w" -gt 40 ]; }; then
        new_off=$(( cur_off + 10 )); [ "$new_off" -gt "$want" ] && new_off=$want
        ec_rw "$CTGP_OFF" "$new_off" >/dev/null
        echo "$(date '+%F %T') release total=${total}W cTGP ${cur_off}->${new_off}" >> "$LOG"
        cur_off=$new_off
      fi
      printf "gpuW=%s cpu%%=%s est=%sW ctgp_off=%s %s\n" "$w" "$u" "$total" "$cur_off" "$(date '+%F %T')" > "$GSTATE"
    fi
    sleep 1
  done
  ;;
*)
  echo "用法: ecguard arm|status|release" >&2; exit 1 ;;
esac
