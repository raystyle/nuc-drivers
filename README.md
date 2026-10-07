# nuc-fantool

Intel NUC X15(Uniwill 准系统,LAPKC71F / LAPKC71E / 麦本本 X568 等同板机型)Linux 自动温控风扇服务。

定位与 NUCtool 对齐:机器过热自动起风扇,温度回落自动降,无需手动干预;CPU 主扇(fan1)保持 EC 原生自治不受干扰,本服务补的是 GPU/副扇(fan2)的温控闭环。

## 原理

- EC 寄存器 `0x60`:fan2 电压档脉冲写入,值会被 EC 周期回收,须循环维持(实测 `0x07` 约 1963 RPM,`0x10` 脉冲爬升,`0x01` 停转)
- EC 寄存器 `0x6A`:性能键状态(本机空态 `0x41`)
- 温度与转速读数(v2.2 起,uniwill hwmon 已让位键盘背光栈,见下节):
  - CPU 温度 = `coretemp` hwmon 各核心最大值;GPU 温度 = `nvidia-smi`
  - 转速 = `/dev/ec` 映像 BE16 读数:`0x64`(fan1)/`0x6C`(fan2)
  - (v2.1 及以前:主线 `uniwill_laptop` hwmon 直读,升级键盘背光栈后不可用)
- EC 用户态通道:`acpi_ec` 树外模块暴露 `/dev/ec`(扁平映像,`dd` 偏移读写)

## 键盘背光(v2.3,ITE 8291 HID 直驱)


真相(2026-10-07 实证):**这块板的键盘灯不归 EC 管**。uniwill EC 的 0x078c/0x1802 寄存器
写入全被接受但物理无效(差分实验零字节联动);灯控在 **ITE 8291 USB HID 芯片(048d:6006,
/dev/hidraw0)**。tuxedo ite_8291 驱动别名表只有 6004/600A/600B 不含 6006,故从不绑定;
上游(Wer-Wolf#17、Armin Wolf 补丁)同证:EC 的 kbd LED 不驱动灯,bit0 探测位已被标 unreliable。

- 协议(tuxedo-drivers ite8291_write_rows 提炼):feature `08 02 33 00 <亮 0-0x32>...` 设模式
  与全局亮度;每行 feature `16 00 <行>...` 宣告 + 62 字节 output `[00 00][B*20][G*20][R*20]`,共 6 行
- 旋钮(需 root,/dev/hidraw0):`sudo kbdlight`(查态)| `sudo kbdlight 50`(亮度 0-100%)|
  `sudo kbdlight 80 FFA500`(亮度 + 颜色 RRGGBB);状态落 /run/kbdlight.state(芯片现值不可读)
- 附带栈(触控板/飞行模式等 uniwill_wmi 面仍需要):`conf/modprobe-tuxedo-uniwill.conf` 保留
  blacklist 主线 uniwill_laptop + uw_force_kbd_type=1;EC 背光寄存器路径仅历史参考
- 开机默认白光:`kbdlight-default.service`(oneshot,白 50%,hidraw 15x2s 就绪重试窗);
  改默认亮度/颜色用 `sudo systemctl edit kbdlight-default` 覆写 ExecStart 后 `systemctl restart` 生效

## 温控曲线(默认,可覆盖)

| 最高温(CPU 与 GPU 取高) | fan2 目标 |
| --- | --- |
| 低于 60 摄氏度 | 0(不干预,显式停转) |
| 60 至 69 | 2500 RPM |
| 70 至 79 | 3500 RPM |
| 80 以上 | 5000 RPM |

滞回 3 摄氏度防抖。阈值与目标经环境变量覆盖:`T1/T2/T3`(档温)与 `R0/R1/R2/R3`(目标 RPM)加 `HYST`。

## 安装(Ubuntu 26.04,内核 7.0 实测)

```bash
git clone https://github.com/raystyle/nuc-fantool
cd nuc-fantool
sudo sh install.sh
```

install.sh 做:编译装 `acpi_ec` 模块并配开机自动加载;装键盘背光双 conf(blacklist 主线 uniwill + 强制 tuxedo type);装 `fanctl-omc.sh` 与 systemd 服务 `fanctl-omc` 并 `enable --now`;装 `kbdlight` 背光旋钮。

## 用法与状态

```bash
systemctl status fanctl-omc                          # 服务态
sudo journalctl -u fanctl-omc -f                     # 温度与目标切换日志
```

改曲线(示例:65 度起、顶档 4500):

```bash
sudo systemctl edit fanctl-omc
# [Service]
# Environment=T1=65 R1=2600 R3=4500
sudo systemctl restart fanctl-omc
```

状态栏 UI(内置扩展):顶栏右侧常显「最高温°C fan1·fan2→目标」(如 `48°C 1350·0→0`),数据源为本服务状态文件加 uniwill hwmon,两秒刷新。装后**注销重登一次**激活(Wayland 下 Shell 不热载新扩展):

```bash
gnome-extensions enable fantool@nuc-fantool   # 重登后执行,或经 install.sh 已自动
```

## 可选:uniwill 树外驱动(EC 杂项)

主线 `uniwill_laptop` 已供全部读数;树外版(Wer-Wolf 上游)另给 fn_lock、触摸板开关、灯动画等 EC 功能,内核 7.0 须打本仓补丁:

```bash
git clone https://github.com/Wer-Wolf/uniwill-laptop
cd uniwill-laptop
patch -p1 < ../patches/uniwill-laptop-kernel7.0.patch
make
sudo modprobe -r uniwill_laptop && sudo insmod uniwill-laptop.ko
```

补丁内容:内核 7.0 清理适配(头文件迁移、LED 多色 API 移除后灯面 stub、WMI 事件成员移除);灯条控制因此牺牲,EC 主功能无恙。非常驻,重启自动回主线版。

## 性能三档(perfmode v1.0)

NUC X15 性能键三档(无灯省电/左灯平衡/两灯性能)在 Linux 无接口:键停 atkbd e078、
EC 0x0751 档位寄存器写入被吞、tuxedo_io ioctl 空转、DPTF/platform_profile 缺位
(2026-10-07 全实证;AMW0 WMI 族经研判为微软示例壳 + 无文档 OEM 体,SET 路径禁探)。

解 = 硬件实效道,档位语义对齐 Intel NUC Software Studio Performance Tuning:

- GPU TGP = Uniwill EC cTGP(Wer-Wolf 语义,同板 LAPKC71E 实证):0x0743 控制位、
  0x0744 偏移瓦数、0x0745 TPP、0x0746 DB 偏移;本机基线 80W,nvidia-smi 功率墙实时可验
- CPU = powercap PL1/PL2 + intel_pstate EPP

| 档位 | GPU 功率墙 | PL1/PL2 | EPP |
| --- | --- | --- | --- |
| battery-saver | 80W(DB 关,ctrl 0x05) | 28/45W | balance_power |
| balanced | 100W + DB25(动态至 125) | 45/65W(出厂) | balance_performance |
| performance | 125W 硬顶(DB 关) | 30/45W | performance |

> 2026-10-07 压测断电教训:GPU 145W(DB)+CPU PL1 50W 合计约 240W 超适配器(约 180W 砖)
> 致 EC 硬切(断前 CPU 仅 85C/GPU 50C、零 OS 告警、journal 硬止,验尸为电源过载非热跳闸)。
> performance 档已重校:GPU 125W 硬顶 + CPU PL1 30W,总包对齐 180W 圈;双满形态禁用。
> 压测须分阶段(CPU-only → GPU-only → 合成),禁一步双满。

用法:`sudo perfmode`(看现态)| `sudo perfmode performance|balanced|battery-saver`
(别名 perf/bal/save 与中文档名亦收);状态落 /run/perfmode.state。
两颗模式灯维持无接口(灯为 cosmetic,硬件实效以功率墙为准)。

## 风险与回滚

- EC 直写有硬件风险,仅适配上述 Uniwill 准系统机型;`0x60` 只影响 fan2
- 服务停止或重启后,EC 回收脉冲,fan2 回落自治(fan1 全程不受影响)
- 完全卸载:`sudo systemctl disable --now fanctl-omc && sudo rm /usr/local/bin/fanctl-omc.sh /etc/systemd/system/fanctl-omc.service /usr/local/bin/kbdlight /etc/modprobe.d/tuxedo-uniwill.conf /etc/modules-load.d/tuxedo-drivers.conf && sudo modprobe -r acpi_ec && sudo rm /lib/modules/$(uname -r)/extra/acpi_ec.ko /etc/modules-load.d/acpi_ec.conf`
- 恢复主线 `uniwill_laptop`(弃键盘背光换回 hwmon 直读):删 `/etc/modprobe.d/tuxedo-uniwill.conf` 后重启,并把 fanctl-omc.sh 回退 v2.1
- 内核升级后需重跑 install.sh 重编 acpi_ec
