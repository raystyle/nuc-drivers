#!/bin/bash
# fanctl-omc v2: NUC X15 (LAPKC71F) auto thermal fan controller (NUCtool 定位)
# CPU 扇(fan1)恒 EC 自治;本服务控 GPU/Secondary 扇(fan2),EC 0x60 脉冲写入
# 曲线按 CPU 与 GPU 温度较高者驱动;阈值与目标可环境变量覆盖
HW=$(for d in /sys/class/hwmon/hwmon*; do [ "$(cat $d/name 2>/dev/null)" = uniwill ] && echo $d && break; done)
[ -z "$HW" ] && { echo "fanctl-omc: no uniwill hwmon" >&2; exit 1; }
w60() { printf "\\x$1" | dd of=/dev/ec bs=1 seek=96 conv=notrunc 2>/dev/null; }
trd() { awk -v t="$(cat $HW/$1 2>/dev/null || echo 0)" 'BEGIN{print int(t/1000)}'; }
T1=${T1:-60}; T2=${T2:-70}; T3=${T3:-80}
R0=${R0:-0}; R1=${R1:-2500}; R2=${R2:-3500}; R3=${R3:-5000}
HYST=${HYST:-3}
cur=-1
while :; do
  c=$(trd temp1_input); g=$(trd temp2_input)
  t=$(( c > g ? c : g ))
  if   [ $t -ge $T3 ]; then tgt=$R3
  elif [ $t -ge $T2 ]; then tgt=$R2
  elif [ $t -ge $T1 ]; then tgt=$R1
  elif [ $t -ge $((T1-HYST)) ] && [ "$cur" -gt 0 ]; then tgt=$R1
  else tgt=$R0; fi
  if [ "$tgt" -ne "$cur" ]; then cur=$tgt; echo "$(date '+%F %T') T=${t}C(cpu=$c gpu=$g) fan2-target=$cur"; fi
  r=$(cat $HW/fan2_input 2>/dev/null || echo 0)
  if [ "$cur" -gt 0 ]; then
    if   [ "$r" -lt $((cur-100)) ]; then for i in 1 2 3 4 5; do w60 10; sleep 0.7; done
    elif [ "$r" -gt $((cur+100)) ]; then w60 07; sleep 5
    else sleep 2; fi
  else
    [ "$r" -gt 200 ] && w60 01
    sleep 5
  fi
done
