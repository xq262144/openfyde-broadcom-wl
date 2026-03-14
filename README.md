# openFyde r126 Broadcom `wl` patchset and build pipeline

目标环境固定为:

- openFyde `r126`
- kernel `5.4.275-22664-gca5ac6161115`
- Broadcom / Apple Wi-Fi `14e4:43a0` (`BCM4360/3`)

这个目录走的是 Broadcom 官方 `wl` 驱动路线，不再继续尝试让 `brcmfmac` 适配 `BCM4360`。

本文档默认你当前就在这个目录里执行命令，也就是:

```sh
cd openfyde-broadcom-wl
```

## 为什么改走 `wl`

对 `14e4:43a0` 来说，当前 ChromeOS / openFyde 这条 `5.4` 内核树里的 `brcmfmac` 没有完整 `BCM4360` 支持，但 Broadcom 官方 `hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz` 里:

- `wl_linux.c` 注册了覆盖面很广的 PCI 表
- `wlc_hybrid.o_shipped` 里包含明确的 `4360` 相关符号

这条线更接近“能让设备起来”的现实路径。

## 这里做了什么

这套流水线会:

1. 准备与你目标版本一致的 ChromiumOS `5.4.275` 内核树
2. 解压当前目录里的官方 Broadcom `wl` 源包
3. 应用一组面向 `5.4` 的兼容 patch
4. 编译 `wl.ko`
5. 打包安装脚本、卸载脚本和 modprobe 黑名单配置
6. 把保守 workaround 一起打进去:
   - `options wl nompc=1`
   - `udev` hook: 接口出现时执行 `iwconfig <iface> power off`
7. 提供一条不依赖 `shill + nl80211` 的 WEXT helper 路线
8. 提供一个开机一次性执行的 WEXT autoconnect job

## patch 来源

兼容 patch 主要参考了 Arch Linux `broadcom-wl-dkms` 的维护思路:

- `4.11` 相关的 `last_rx` / `sched/signal.h`
- `4.15` timer API 适配
- Arch 包里对 `Makefile` 的 `GE_49 := 1` 处理
- Arch 的 blacklist 配置

另外补了一个 `4.14 kernel_read()` 原型兼容 patch，用于当前 `5.4`。

## 当前保留内容

这个目录现在只保留可复用内容:

- `patches/`: `wl` 驱动 patchset
- `scripts/`: 构建、打包和本地 release 脚本
- `broadcom-wl-dkms.conf`: 参考 Arch 的 blacklist 配置
- `helpers/`: release 包里会生成一个接口级省电关闭脚本
- `helpers/broadcom-wl-openfyde-wext-connect`: 手工 WEXT 连接脚本
- `helpers/broadcom-wl-openfyde-wext-disconnect`: 手工 WEXT 清理脚本
- `helpers/broadcom-wl-openfyde-autoconnect`: 开机一次性 WEXT 自连入口
- `helpers/broadcom-wl-openfyde-dhclient-script`: `dhclient` 地址/路由应用脚本
- `configs/broadcom-wl-openfyde-autoconnect.conf`: Upstart job
- `configs/broadcom-wl-openfyde.conf.example`: 示例配置
- `Dockerfile`: `linux/amd64` 构建环境
- `README.md`: 过程说明和复现方法

以下内容不再保留在仓库里，按需重新生成:

- `build/`: 内核源码树和解压后的官方驱动源码
- `out/`: 构建出的模块
- `dist/`: 打包产物

## 构建输入

当前目录默认直接放构建输入文件:

```sh
config.gz
hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz
```

其中:

- `config.gz`: 目标 openFyde 机器导出的内核配置压缩包
- `hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz`: Broadcom 官方 `wl` 源码包

如果你要重新从目标机导出配置，执行:

```sh
zcat /proc/config.gz > kernel.config
```

当前脚本默认按下面顺序找配置文件:

1. `./config.gz`
2. `./kernel.config`
3. `./kernel.config.gz`
4. `../kernel.config`
5. `../config.gz`

所以你现在这种“把 `config.gz` 直接放在当前目录”的方式，是默认支持的，不需要额外传参。

Broadcom 官方 tarball 也默认从当前目录读取:

```sh
./hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz
```

如果没有真实配置，也可以先做 `smoke` 编译验证 patchset 和产物是否能出。

如果目标机器的 `uname -r` 带额外后缀，比如 `-dirty`，构建时显式传入:

```sh
LOCALVERSION=-22664-gca5ac6161115-dirty \
TARGET_KERNEL_RELEASE=5.4.275-22664-gca5ac6161115-dirty \
BUILD_MODE=release \
./scripts/release_local.sh
```

## 复现构建

### Smoke build

```sh
BUILD_MODE=smoke ./scripts/release_local.sh
```

### Release build

```sh
BUILD_MODE=release ./scripts/release_local.sh
```

`release` 模式默认读取:

```sh
./config.gz
```

如果你想覆盖默认输入，也可以显式指定:

```sh
CONFIG_FILE=./kernel.config \
SOURCE_TARBALL=./hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz \
BUILD_MODE=release \
./scripts/release_local.sh
```

## 构建后会生成什么

重新构建后，产物位于:

```sh
./dist/
```

每个 release 包里会包含:

- `modules/wl.ko`
- `configs/broadcom-wl-dkms.conf`
- `configs/99-broadcom-wl-openfyde.rules`
- `configs/broadcom-wl-openfyde-autoconnect.conf`
- `configs/broadcom-wl-openfyde.conf.example`
- `helpers/broadcom-wl-openfyde-post-up`
- `helpers/broadcom-wl-openfyde-autoconnect`
- `helpers/broadcom-wl-openfyde-dhclient-script`
- `helpers/broadcom-wl-openfyde-wext-connect`
- `helpers/broadcom-wl-openfyde-wext-disconnect`
- `install-module.sh`
- `uninstall-module.sh`
- `patches/`
- `manifest.txt`

## 安装 release 包

在目标 openFyde 机器上解压 release 包，然后执行:

```sh
./install-module.sh
```

如果你是 `root`，直接执行就行；如果不是 `root`，脚本会自动走 `sudo`。

如果你当前就是通过这台机器的网络远程连进去，不想在安装瞬间把自己踢下线，可以先只落盘不现场重载:

```sh
SKIP_LIVE_RELOAD=1 ./install-module.sh
```

安装脚本会:

- 把 `wl.ko` 装到 `/lib/modules/<kernel>/extra/broadcom-wl/`
- 写入 `modprobe.d` blacklist，禁用 `bcma` / `brcmfmac` / `ssb` 等冲突驱动
- 写入 `options wl nompc=1`
- 写入 `modules-load.d/wl.conf`
- 安装 `udev` rule 和 `/usr/local/sbin/broadcom-wl-openfyde-post-up`
- 在接口出现时自动执行 `iwconfig <iface> power off`
- 安装 WEXT helper、`dhclient` hook 和 Upstart autoconnect job
- 如果 `/usr/local/etc/broadcom-wl-openfyde.conf` 不存在，会从 example 自动生成一份
- 发现根分区当前是只读时，会临时 `remount,rw`，写完后 `sync` 并恢复为只读
- 运行 `depmod`
- 清理残留的 Broadcom PCI `driver_override`
- 重新加载 `wl`，立即带上 `nompc=1`
- 尝试把 Broadcom 无线设备立即重绑到 `wl`
- 在线对当前无线接口先执行一次 `power off`

装完建议马上检查:

```sh
lspci -nnk -d 14e4:43a0
iw dev
ip link show wlan0
dmesg | grep -i wl
```

## 当前已确认的关键结论

对这台 openFyde r126 机器，问题不只是内核模块加载，而是用户态接口匹配:

- `wl` 驱动能正常起卡、扫描、完成 WPA 握手
- 但 openFyde / ChromiumOS 的 `shill` 通过 `wpa_supplicant` 走的是 `nl80211`
- `wl` 在这条链路下持续报 `CTRL-EVENT-SCAN-FAILED ret=-22`
- 连接会在 `association` 超时后被 `shill` 记成 `unknown-failure`
- 一旦改走 `wpa_supplicant -Dwext`，这台机子能稳定连上目标 SSID 并拿到 IPv4
- 远端已经实测过 `wlan0=192.0.2.10/24`，`ping -I 192.0.2.10 192.0.2.1` 可通
- 当 `wlan0` 抢到可用路由后，原来的跳板 SSH 入口可能失效，后续应直接改用 `ssh root@<wlan_ip>`

实际远端验证过的 workaround 是:

- 让 `shill` 暂时停止管理 Wi-Fi
- 手工启动 `wpa_supplicant -Dwext`
- 再用 `dhclient` 在 `wlan0` 上拿地址

这条 WEXT 路线已经在目标机上实测成功:

- `iw dev wlan0 link` 显示已连上目标 SSID
- `wpa_supplicant` 日志出现:
  - `WPA: Key negotiation completed`
  - `CTRL-EVENT-CONNECTED`
- `dhclient` 成功给 `wlan0` 配上 IPv4 和默认路由
- 之前实验里 `dhcpcd -4 -w wlan0` 曾出现孤儿进程自旋打满 CPU，所以当前 helper 已全部切到 `dhclient`

## 手工 WEXT workaround

release 包里会带两个 helper:

```sh
./helpers/broadcom-wl-openfyde-wext-connect <your-ssid>
./helpers/broadcom-wl-openfyde-wext-disconnect
```

`broadcom-wl-openfyde-wext-connect` 会:

- 从本机保存的 shill profile 中读取该 SSID 的密码
- 暂时禁用 shill 的 Wi-Fi 管理
- 对 `wlan0` 启动 `wpa_supplicant -Dwext`
- 关联成功后运行 `dhclient -4 -nw`
- 用单独的 `dhclient` hook 给 `wlan0` 配地址和默认路由

`broadcom-wl-openfyde-wext-disconnect` 会:

- 停掉手工启动的 `wpa_supplicant`
- 停掉手工 `dhclient`
- 清理 `wlan0` 地址
- 把 Wi-Fi 交还给 shill

## 开机自动连接

release 包还会安装:

- `/usr/local/sbin/broadcom-wl-openfyde-autoconnect`
- `/usr/local/etc/broadcom-wl-openfyde.conf`
- `/etc/init/broadcom-wl-openfyde-autoconnect.conf`

默认行为是:

- `shill` 和 `ui` 都起来后，Upstart 只运行一次 autoconnect helper
- helper 默认先等待 `15s`
- helper 会等待 `wlan0` 和 `org.chromium.flimflam` 出现
- helper 还会等待保存的 `SSID` 凭据出现在本地 shill profile 中
- 如果 `wlan0` 已经联通并且已有 IPv4，就直接退出，不重复折腾当前连接
- 否则读取 `/usr/local/etc/broadcom-wl-openfyde.conf` 里的 `SSID`
- 再调用 `broadcom-wl-openfyde-wext-connect`
- helper 自带固定 `PATH`，不依赖 Upstart 默认环境
- helper 日志默认写到:
  - `/mnt/stateful_partition/var/log/broadcom-wl-openfyde-autoconnect.log`

默认配置示例:

```sh
SSID=YOUR_WIFI_SSID
IFACE=wlan0
INITIAL_DELAY=15
WAIT_SECONDS=90
STATUS_LOG=/mnt/stateful_partition/var/log/broadcom-wl-openfyde-autoconnect.log
```

如果只想测试 autoconnect job 本身，不需要重启，可以在目标机上执行:

```sh
start broadcom-wl-openfyde-autoconnect
```

这个 job 被设计成 `task`，不是 `respawn` 型 service，避免连上后又反复重跑。

如果开机没有自动连上，优先检查:

```sh
initctl status broadcom-wl-openfyde-autoconnect
sed -n '1,200p' /mnt/stateful_partition/var/log/broadcom-wl-openfyde-autoconnect.log
```

这次真实问题就是:

- job 确实被触发了
- 但它在开机时以 `status 1` 退出
- 手工 root shell 能跑，是因为交互 shell 的 `PATH` 包含 `/usr/sbin` 和 `/usr/local/sbin`
- 开机 Upstart 环境更瘦，旧版本 helper 没有自带 `PATH`，会导致 `iwconfig` / `wpa_supplicant` / `dhclient` 这类命令找不到

## `dmesg` 里的严重问题

目前可以分成两层看:

1. 现在可绕过的问题
   - `shill + nl80211 + wl` 这条链路不稳定
   - WEXT workaround 能让机器正常联网，所以当前“能用”的路径是成立的

2. 还没根治的内核问题
   - `dmesg` 里反复出现:
     - `WARNING ... cfg80211_connect_result`
     - `WARNING ... cfg80211_roamed`
   - 调用栈直接落在:
     - `wl_bss_roaming_done.isra.0 [wl]`
     - `wl_notify_roaming_status [wl]`
     - `wl_event_handler [wl]`
   - 这说明 `wl_cfg80211_hybrid.c` 的 `cfg80211` glue 仍然有 API 使用错误

所以当前结论是:

- 对“先让机器联网”这个目标，问题严重但可绕过
- 对“让 `shill/cfg80211` 路线完全健康”这个目标，问题仍然严重，后续要继续修 `wl` 的 `cfg80211` 兼容层

## 清理策略

这个目录默认不保留大文件和生成物。需要重新构建时，按上面的输入准备好:

- 当前目录里的 Broadcom 官方 tarball
- 当前目录里的 `config.gz`，或者你显式指定的 `CONFIG_FILE`

然后重新执行 `release_local.sh` 即可恢复 `build/`、`out/`、`dist/`。

## 现实限制

- 这套 patchset 和 helper 已经在目标 openFyde 机器上完成过实际联网验证
- 但“默认 `shill + nl80211` 路线完全健康”这件事还没做到，当前稳定方案仍然是 WEXT workaround
- 如果你要继续走 release pipeline 重新发包，还是应该尽量使用目标机真实 `config.gz`

## 建议的真机验证顺序

```sh
uname -r
lspci -nnk -d 14e4:43a0
iw dev
ip -4 addr show dev wlan0
ip route show dev wlan0
ping -I "$(ip -4 -o addr show dev wlan0 | awk '{print $4}' | cut -d/ -f1)" -c 2 <gateway_ip>
```

如果上面这组验证通过，再看:

```sh
dmesg -T | egrep -i 'wl|cfg80211|wlan0|Call Trace|WARNING'
```

这样可以把“网络是否可用”和“驱动内部是否仍有告警”分开判断。
