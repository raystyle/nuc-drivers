#!/bin/bash
# fanctl-omc v2.2: NUC X15 (LAPKC71F) auto thermal fan controller (NUCtool 定位)
# CPU 扇(fan1)恒 EC 自治;本服务控 GPU/Secondary 扇(fan2),EC 0x60 脉冲写入
# 曲线按 CPU 与 GPU 温度较高者驱动;阈值与目标可环境变量覆盖
# 状态文件 /run/fanctl-omc.state 供 fantool 顶栏扩展消费
#
# v2.2 数据源变更:内核 uniwill_laptop 驱动(uniwill hwmon)已由 tuxedo-drivers
# 取代(blacklist,为修复键盘背光),数据源改为:
#   CPU 温度 = coretemp hwmon 各核心最大值
#   GPU 温度 = nvidia-smi
#   转速     = /dev/ec 映像 BE16 @0x64(fan1)/@0x6C(fan2),acpi_ec 模块提供
# 开机等待 /dev/ec 就绪(模块经 DKMS 自动加载)

# 等待 /dev/ec(最多约 30 秒)
i=0; while [ ! -e /dev/ec ] && [ $i -lt 15 ]; do sleep 2; i=$((i+1)); done
[ -e /dev/ec ] || { echo "fanctl-omc: /dev/ec not available" >&2; exit 1; }

w60() { printf "\\x$1" | dd of=/dev/ec bs=1 seek=96 conv=notrunc 2>/dev/null; }
rpm() { od -An -tu2 --endian=big -j$1 -N2 /dev/ec 2>/dev/null | tr -d ' \n'; }
cpu_t() { local d t m=0 v
  for d in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$d/name" 2>/dev/null)" = coretemp ] || continue
    for t in "$d"/temp[0-9]_input; do
      [ -r "$t" ] || continue
      v=$(cat "$t" 2>/dev/null || echo 0); [ "$v" -gt "$m" ] && m=$v
    done
  done
  echo $((m/1000)); }
gpu_t() { local g
  g=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1 | tr -dc '0-9')
  echo "${g:-0}"; }
T1=${T1:-60}; T2=${T2:-70}; T3=${T3:-80}
R0=${R0:-0}; R1=${R1:-2500}; R2=${R2:-3500}; R3=${R3:-5000}
HYST=${HYST:-3}
cur=-1
while :; do
  c=$(cpu_t); g=$(gpu_t)
  t=$(( c > g ? c : g ))
  if   [ $t -ge $T3 ]; then tgt=$R3
  elif [ $t -ge $T2 ]; then tgt=$R2
  elif [ $t -ge $T1 ]; then tgt=$R1
  elif [ $t -ge $((T1-HYST)) ] && [ "$cur" -gt 0 ]; then tgt=$R1
  else tgt=$R0; fi
  if [ "$tgt" -ne "$cur" ]; then cur=$tgt; echo "$(date '+%F %T') T=${t}C(cpu=$c gpu=$g) fan2-target=$cur"; fi
  r=$(rpm 108); r=${r:-0}
  f1=$(rpm 100); f1=${f1:-0}
  printf "cpu=%s gpu=%s fan1=%s fan2=%s target=%s %s\n" "$c" "$g" "$f1" "$r" "$cur" "$(date '+%F %T')" > /run/fanctl-omc.state
  if [ "$cur" -gt 0 ]; then
    if   [ "$r" -lt $((cur-100)) ]; then for i in 1 2 3 4 5; do w60 10; sleep 0.7; done
    elif [ "$r" -gt $((cur+100)) ]; then w60 07; sleep 5
    else sleep 2; fi
  else
    [ "$r" -gt 200 ] && w60 01
    sleep 5
  fi
done
