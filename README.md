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

## 键盘背光(v2.2)

内核自带 `uniwill_laptop` 抢占 Uniwill WMI 设备,致 tuxedo 栈无法 probe,键盘背光无人驱动。
处置 = blacklist 主线 + tuxedo 全权接管(本机型 barebone ID 0x08 不在 tuxedo 已知列表,
实测两级定色白光,须 `uw_force_kbd_type=1` 强制):

- `conf/modprobe-tuxedo-uniwill.conf` → `/etc/modprobe.d/tuxedo-uniwill.conf`(blacklist 双模块 + 强制 type)
- `conf/modules-load-tuxedo-drivers.conf` → `/etc/modules-load.d/tuxedo-drivers.conf`(开机拉 uniwill_wmi)
- 控制面 = `/sys/devices/platform/tuxedo_keyboard/leds/white:kbd_backlight`(0/1/2,sysfs 钳制)
- 旋钮:`sudo kbdlight`(查档)| `kbdlight 2`(设档)| `kbdlight +1`(相对调)

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

## 风险与回滚

- EC 直写有硬件风险,仅适配上述 Uniwill 准系统机型;`0x60` 只影响 fan2
- 服务停止或重启后,EC 回收脉冲,fan2 回落自治(fan1 全程不受影响)
- 完全卸载:`sudo systemctl disable --now fanctl-omc && sudo rm /usr/local/bin/fanctl-omc.sh /etc/systemd/system/fanctl-omc.service /usr/local/bin/kbdlight /etc/modprobe.d/tuxedo-uniwill.conf /etc/modules-load.d/tuxedo-drivers.conf && sudo modprobe -r acpi_ec && sudo rm /lib/modules/$(uname -r)/extra/acpi_ec.ko /etc/modules-load.d/acpi_ec.conf`
- 恢复主线 `uniwill_laptop`(弃键盘背光换回 hwmon 直读):删 `/etc/modprobe.d/tuxedo-uniwill.conf` 后重启,并把 fanctl-omc.sh 回退 v2.1
- 内核升级后需重跑 install.sh 重编 acpi_ec
