#!/bin/bash
# fanctl-omc v2.4: NUC X15 (LAPKC71F) 纯遥测(零 EC 写,双扇 EC 全自治)
# v2.4 断代:三案验尸(2026-10-07)证 EC 自治足以压温,0x60 写手纯冗余故全部移除;
# 断电护栏职责移交 ecguard(充电档案 stationary + GPU 跌落观测)。target=auto 只展示
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
smi_query() {  # 一次双查:温度 + 功率
  nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1; }
SMI=$(smi_query)
gpu_t() { local g=${SMI%%,*}; g=$(echo "$g" | tr -dc '0-9'); echo "${g:-0}"; }
gpu_w() { local w=${SMI##*,}; w=$(echo "$w" | tr -dc '0-9.'); echo "${w%.*}"; }
RAPL_E=$(ls /sys/class/powercap/intel-rapl*/energy_uj 2>/dev/null | head -1)
cpu_w_prev=$(cat "$RAPL_E" 2>/dev/null || echo 0)
t_prev=$EPOCHREALTIME
cpu_w() { local e now d
  e=$(cat "$RAPL_E" 2>/dev/null || echo 0); now=$EPOCHREALTIME
  d=$(awk -v a="$t_prev" -v b="$now" 'BEGIN{print b-a}')
  [ -z "$RAPL_E" ] && { echo 0; return; }
  awk -v e1="$cpu_w_prev" -v e2="$e" -v dt="$d" 'BEGIN{
    d=e2-e1; if (d<0) d+=262143999999; printf "%d", (dt>0)? d/1000000/dt : 0}'
  cpu_w_prev=$e; t_prev=$now; }
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
  if [ "$tgt" -ne "$cur" ]; then cur=$tgt; echo "$(date '+%F %T') T=${t}C(cpu=$c gpu=$g) ec-would-target=$cur (auto)"; fi
  r=$(rpm 108); r=${r:-0}
  f1=$(rpm 100); f1=${f1:-0}
  cw=$(cpu_w); gw=$(gpu_w); SMI=$(smi_query)
  printf "cpu=%s gpu=%s fan1=%s fan2=%s target=auto cpuW=%s gpuW=%s %s\n" "$c" "$g" "$f1" "$r" "$cw" "$gw" "$(date '+%F %T')" > /run/fanctl-omc.state
  sleep 3
done
