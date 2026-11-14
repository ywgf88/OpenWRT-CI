# OpenWRT-CI · ImmortalWrt 云编译自用仓库

自用的 ImmortalWrt GitHub Actions 云编译仓库，源码基于 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) 的 `owrt` 分支（上游为 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)）。编译核心抽成可复用的 `WRT-CORE.yml`，各平台 workflow 通过矩阵传入配置与默认参数。固件默认**仅 IPv4**、默认主题 **Vantage**、默认管理地址 **192.168.100.1**，成品发布在本仓库 [Releases](../../releases)。

> 当前仅启用 **qualcommax / IPQ60XX** 一条流水线（Redmi AX5）。AIROHA、MTK、OWRT(ROCKCHIP/X86)、QCB 等平台 workflow 与对应配置已移入 `disabled/` 目录，不参与编译。

## 固件概览

| 项目 | 说明 |
| --- | --- |
| 设备平台 | `qualcommax` / `ipq60xx`，配置 `CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_redmi_ax5=y`（Redmi AX5） |
| 源码 | `VIKINGYFY/immortalwrt` @ `owrt` |
| 配置文件 | `Config/IPQ60XX-WIFI-YES.txt`（设备与精简项）+ `Config/GENERAL.txt`（全平台公共项） |
| 默认管理地址 | **192.168.100.1**，用户名 `root`，默认**空密码**（首次登录请立即设置） |
| 默认主题 | **Vantage**（`anothaDev/luci-theme-vantage`）；`Scripts/Packages.sh` 另预置 Argon / Aurora / Fluent / Footstrap / Kucat / Shadcn 源码，改 `WRT_THEME` 即可切换 |
| 默认主机名 | `OWRT` |
| 默认 Wi-Fi | SSID `OWRT`，密码 `12345678` |
| 默认网络 | 仅 IPv4：`Scripts/IPv4-Default.sh` 关闭 ULA / ip6assign / wan6 / RA / DHCPv6 / NDP，并在首启脚本中兜底清理；需要 IPv6 可在 LuCI 手动开回 |
| 中文界面 | `CONFIG_LUCI_LANG_zh_Hans=y` |
| 产物 | `*-squashfs-factory.ubi`（首次刷入）、`*-squashfs-sysupgrade.bin`（升级）、`.manifest`、`Config-*.txt` |
| 版本标识 | `WRT_DATE` 以 `TZ=UTC-8` 取**编译开始时刻**，写入文件名、Release tag 与 LuCI 页脚，便于对照上游 commit |
| 内核 | 随上游浮动，以 Release 说明中的「内核版本」为准（2026-11-14 产物为 `6.18.60`） |
| 镜像体积 | 精简后 `squashfs-sysupgrade.bin` **40.96 MiB**、`squashfs-factory.ubi` **42.62 MiB**（精简前 54.49 / 56.62 MiB） |

> `WRT_PW` 仅为 Release 文案里的提示字段，修改它**不会**改变固件登录密码；密码始终需要首次登录后自行设置。产物按平台打包，刷机前请核对设备型号、分区布局与 factory/sysupgrade 用途。

## 固件精简与空间（自用定制）

按 **Redmi AX5（RA67，IPQ6000，无 USB / 无 SATA / 无 NVMe / 无 SD / 无声卡）** 的实际硬件做体系化裁剪，目标是压镜像换 overlay。

* **累计从 `Config/GENERAL.txt` 删除 64 行配置**：51 项 USB / 磁盘 / 文件系统类驱动与工具 + 9 项文件共享与分区插件 + 4 项冗余插件（`luci-app-gecoosac`、`stuntman-client`、`luci-proto-relay`、`fullconenat-sonic`）。
* **连带掉 55 个依赖包**：manifest 包数 `377 → 322`（关闭 `luci-app-fullconenat-sonic` 后为 **320**）。删一个插件常拉走一串依赖——`samba4` 带走 `gnutls`/`wsdd2`/`libtirpc`，`partexp` 带走 `parted`/`libparted`/`resize2fs`，`gecoosac` 带走 `avahi`/`dbus` 全家，`btrfs-progs` + `kmod-fs-btrfs` 带走一串 `kmod-lib-*`。
* **有些包删配置行没用**：`luci-app-fullconenat-sonic` 和 `fullconenat-sonic` 的 Makefile 里都写了 `DEFAULT:=y if … firewall`，只要 firewall 在就自动启用；要去掉必须在 `.config` 里显式写 `# CONFIG_PACKAGE_xxx is not set`。
* **镜像体积（2026-11-14 实测）**：`squashfs-sysupgrade.bin` 54.49 MiB → **40.96 MiB（−13.53 MiB）**；`squashfs-factory.ubi` 56.62 MiB → **42.62 MiB（−14.00 MiB）**。
* **删驱动的收益极小，删插件的收益极大**：单项 kmod 只有几 KB~几十 KB，本次 −13.5 MiB 几乎全部来自插件依赖链。要压体积优先动插件，别动 kmod。
* **overlay ≈ 72 MiB − squashfs 镜像体积 − UBI 开销**：镜像每减 1 MiB，`/overlay` 约增 1 MiB（实测 −2.15 MiB 镜像换来 +2.1 MiB overlay）。40.96 MiB 镜像刷入后 **`/overlay` 实测 21.7 MiB（可用 20.5 MiB）**，此前为 9.2 MiB。
* **1G 内存调优（随固件首启生效）**：`Files/etc/uci-defaults/97-ram-tune` 把 dnsmasq 缓存 1500 → 8192、日志环缓冲 → 128KB、内核 `rmem/wmem` 提到 16 MiB、`nf_conntrack_max` 提到 65536；`Files/etc/init.d/homeproxy-ram` 把 homeproxy 看板（约 8 MiB）重定向到 `/tmp`，**用 8 MiB 内存换 8 MiB flash**。
* **不要做 swap / zram**：本机无盘，1G 内存长期用不满，压缩内存是负收益；`/tmp` 也不要塞大文件，默认只占内存一半。

> 未启用 `passwall2`；`luci-app-homeproxy` + `sing-box` 保留。注意 `luci-app-homeproxy` 首次启动会把约 8 MiB 看板资源写进 overlay，可用空间会突然下降，必要时把 `/etc/homeproxy/dashboard` 软链到 `/mnt/data`。

## 大分区与 `/mnt/data`

本机 mibib 是「大分区」布局：`rootfs` 72 MiB（mtd18）+ `overlay` 36.6 MiB（mtd19）。分区表由 bootloader 的 SMEM 表决定（源码 dts 里只有 `partitions { compatible = "qcom,smem-part"; }`），**固件侧改不了分区大小**。

* **OpenWrt / ImmortalWrt 只在 `rootfs` 一块 mtd 上建 ubi0**（576 PEB = 72 MiB），`overlay` 那块从刷机起一直闲置，`/dev` 里没有 `ubi1`。
* `Files/etc/init.d/mtd19-data` 开机时把这块闲置分区建成独立 UBI 卷并挂到 **`/mnt/data`（约 36.6 MiB）**；`Files/etc/uci-defaults/99-mtd19-data` 负责首次启动自动 `enable` 并挂载一次。
* 保护措施：仅对 `redmi,ax5` 生效（按 `/tmp/sysinfo/board_name` 判定）；用 `/sys/class/ubi/ubi1` 判断是否已 attach，**只在分区没有 UBI 头时格式化一次**；`/dev` 为 tmpfs 时按 `/sys` 设备号补建节点；任一步失败只写日志，不阻塞启动。
* 不改分区表、不动 ubi0、不需要 `mkfs.ubifs`（空卷首次挂载由内核初始化 UBIFS）。
* 刷机建议：**用 `factory.ubi` 走不死 uboot 网页刷**，UBI 卷会按新镜像重建、overlay 才会真正扩大；直接 sysupgrade 可能沿用旧卷大小。
* **运行实测（2026-11-14 刷入后）**：`/mnt/data` 已挂载 `ubi1_0`，`/dev` 下出现 `ubi1`、`ubi1_0`；`/overlay` 21.7 MiB。
* **注意 1｜旧卷不会被自动清空**：脚本的安全策略是“分区有 UBI 头就不格式化”。如果这块分区里还留着别的固件（例如 QWRT）建的旧卷，就会直接挂旧卷——实测只剩 28.2 MiB 且带 2020 年的旧数据（`etc` / `userdisk` / `usr`）。要拿满额空间需手工重建，见下。
* **注意 2｜可能被挂两次**：同一卷可能同时出现在 `/mnt/data` 与 `/mnt/ubi1_0`（后者是系统自动挂载），不影响使用。
* **注意 3｜`logread | grep mtd-data` 可能为空**：`uci-defaults` 在 `logd` 启动前执行，`logger` 消息会被丢掉。验证请看 `mount | grep mnt/data` 或 `dmesg | grep -i ubifs`。

重建满额数据卷（会清掉旧数据，按需执行）：

```sh
umount /mnt/data /mnt/ubi1_0 2>/dev/null
ubirmvol /dev/ubi1 -n 0
ubimkvol /dev/ubi1 -N data -m          # -m 取分区最大空间
mount -t ubifs ubi1_0 /mnt/data
df -h /mnt/data
```

**重建后实测**：`ubimkvol` 报 `size 269 LEBs (34156544 bytes, 32.5 MiB)`，即把 36.6 MiB 分区的可用 LEB 吃到 269 个（其余为 UBI 保留与坏块）。空卷 `df` 显示 `28.2M / 24.0K / 26.7M` —— UBIFS 报给 statfs 的口径已扣除索引与保留空间，**32.5 MiB 是卷的物理容量，28.2M 是 `df` 视角的总量**，两者不是矛盾。

## 编译流水线

| Workflow | 触发方式 | 作用 |
| --- | --- | --- |
| `QCA-ALL` | `Auto-Clean` 运行完成后自动触发 / 手动 | 矩阵 `CONFIG=IPQ60XX-WIFI-YES`、`SOURCE=VIKINGYFY/immortalwrt`、`BRANCH=owrt`，调用 `WRT-CORE` 编译并发布 |
| `WRT-CORE` | `workflow_call`（被其他 workflow 调用） | 公共编译核心：安装依赖 → 恢复缓存 → 拉取源码与 feeds → 定制包与配置 → 编译 → 打包发布 → 缓存轮转 |
| `Auto-Clean` | 手动 | 清空全部历史 Releases / Tags / Workflow runs（`releases_keep_latest: 0`），随后经 `workflow_run` 拉起编译 |
| `Cache-Clean` | 手动 | `gh cache delete --all`，清空 Actions 构建缓存 |

`QCA-ALL` 的两个手动输入：

| 输入 | 默认值 | 说明 |
| --- | --- | --- |
| `PACKAGE` | 空 | 追加 `CONFIG_PACKAGE_*=y` 等条目到 `.config`，多项用 `\n` 分隔 |
| `TEST` | `false` | 只生成并上传 `Config-*.txt`，跳过下载、编译与固件打包 |

传给 `WRT-CORE` 的默认参数：`WRT_THEME=vantage`、`WRT_NAME=OWRT`、`WRT_SSID=OWRT`、`WRT_WORD=12345678`、`WRT_IP=192.168.100.1`、`WRT_PW=无`、`WRT_BRANCH=owrt`。

> **定时说明**：现行启用的 workflow 均没有 `schedule` 项，编译由 `Auto-Clean` 的 `workflow_run` 或手动 `workflow_dispatch` 触发。旧版 README 中「每天早上 5 点自动编译」在目前配置下不成立；如需定时，在 `Auto-Clean.yml` 或 `QCA-ALL.yml` 的 `on:` 中自行加入 `schedule: - cron: ...`（注意 GitHub Actions 的 cron 为 UTC）。

## 已集成插件

**`Config/GENERAL.txt` 中显式指定的公共项**

| 分类 | 主要包 |
| --- | --- |
| 代理 / 分流 | `luci-app-homeproxy`、`sing-box`（在设备 config 中启用）、`luci-app-natmapt` |
| 系统 / 运维 | `luci-app-autoreboot`、`luci-app-upnp`、`luci-app-wolultra`、`htop`、`iperf3`、`curl`、`ip-full`、`lsblk`、`nand-utils`、`xz-utils`、`openssh-sftp-server` |
| 内核模块 | `kmod-nft-*`（core / nat / offload / tproxy / queue / socket / fib 等）、`kmod-wireguard`、`kmod-tun`、`kmod-mtd-rw`、`kmod-dsa`、`kmod-inet-diag` |
| 构建开关 | `CONFIG_CCACHE=y`、`CONFIG_DEVEL=y`、`CONFIG_TARGET_MULTI_PROFILE=y`、`CONFIG_TARGET_PER_DEVICE_ROOTFS=y`；关闭 `luci-app-attendedsysupgrade`、`luci-app-wol` 与 `video` / `pon_*` feed |
| 已移除（无对应硬件） | USB 与存储栈（`kmod-usb-*` 全系、`kmod-usb-storage*`、`usbutils`、`usb-modeswitch`、`libimobiledevice`、`usbmuxd`）、`kmod-ata-*`、`kmod-nvme`、`kmod-fs-btrfs`、`kmod-fs-ksmbd`、`mmc-utils`、`smartmontools`、`nvme-cli`、`kmod-sound-core`、`kmod-usb-audio`、`kmod-bonding`、`kmod-veth`、`coremark` |
| 已移除（插件与磁盘工具） | `luci-app-samba4`、`luci-app-partexp`、`luci-app-mini-diskmanager`、`luci-app-gecoosac`、`stuntman-client`、`luci-proto-relay`、`luci-app-fullconenat-sonic`（只删 LuCI 页面；内核模块 `fullconenat-sonic` 仍随 firewall 默认启用）；`automount`、`blkid`、`cfdisk`、`fdisk`、`sfdisk`、`cgdisk`、`gdisk`、`sgdisk`、`exfat-fsck`、`exfat-mkfs`、`kmod-fuse` |

**最近一次 Release 实际装入的 LuCI 应用**（取自 manifest，随上游变动，以 Release 说明的「插件列表」为准）

`luci-app-autoreboot` · `firewall` · `homeproxy` · `natmapt` · `package-manager` · `qca-ppe-qos` · `router-tool` · `upnp` · `vantage` · `wolultra`，主题 `luci-theme-vantage`（2026-11-14 23:23 产物，manifest 共 **320** 个包；精简前为 377 个）。

**`Scripts/Packages.sh` 预置的第三方源**（`UPDATE_PACKAGE` 会先删除 feeds 中的同名目录、再按指定分支克隆到 `package/`，避免版本冲突；是否进入固件仍由 `.config` 决定）

- 主题：`argon` / `aurora` / `aurora-config` / `fluent` / `footstrap` / `kucat` / `kucat-config` / `shadcn` / `vantage`
- 代理：`momo`、`nikki`、`openclash`、`passwall`（`passwall2` 一行已注释）
- 工具与网络：`diskmanager`、`easytier`、`qmodem`、`VIKINGYFY/packages`、`diskman`、`mosdns`、`openlist2`、`qbittorrent`、`quickfile`、`ddns-go`、`netspeedtest`、`netwizard`、`partexp`、`timecontrol`、`natmapt`、`stuntman`、LianXia233 系列（风扇 / 模组 / 网络监控等）
- `UPDATE_VERSION` 可从上游最新 Release 拉取版本号与哈希，默认未启用

> `Config/IPQ60XX-WIFI-YES.txt` 只保留 `sing-box` 作为 HomeProxy 内核，未启用 `passwall2` / `xray-core`，目的是压缩固件体积。`Scripts/PRIVATE.sh` 与 `Config/PRIVATE.txt` 若存在会被自动加载（当前仓库未提交），适合放不便公开的私有插件与配置项。

## 定制点

| 项目 | 脚本 | 内容 |
| --- | --- | --- |
| 默认主题 | `Scripts/Settings.sh` | 将 `feeds/luci/collections` 的 Makefile 中 `luci-theme-bootstrap` 替换为 `$WRT_THEME`，并写入对应 `CONFIG_PACKAGE_*` |
| 默认 IP / 主机名 | `Settings.sh` | 改 `config_generate` 的 IP 与 hostname，同步替换 `flash.js` 中的 `immortalwrt.lan` 关联 IP |
| Wi-Fi | `Settings.sh` | 改 `mac80211.uc` 与 `router-tool` 的 SSID / 密码 |
| 页脚标识 | `Settings.sh` | 在 `10_system.js` 追加 `$WRT_MARK-$WRT_DATE` 编译时间 |
| 纯 IPv4 | `Scripts/IPv4-Default.sh` | 改 `config_generate`、`dhcp.conf`、`firewall.config`，并投放首启脚本 `uci-defaults/99-ipv4-default` |
| 主题与菜单修补 | `Scripts/Handles.sh` | Argon 配色/背景、Aurora 下拉菜单、Vantage 进度条字体、mini-diskmanager 与 natmapt 菜单位置；用 `FIX` 守卫，目录不存在时自动跳过 |
| 高通平台 | `Settings.sh` | 配置名含 `WIFI-NO` 时把 DTS 引用切到 `ipq6018/ipq8074-nowifi.dtsi` 以缩小 Q6 固件 |
| 闲置分区挂载 | `Scripts/Settings.sh` + `Files/` | 把 `Files/etc/init.d/mtd19-data`、`Files/etc/uci-defaults/99-mtd19-data` 安装进 `package/base-files/files/`，开机把 mtd19 建成 UBI 卷挂到 `/mnt/data` |
| 内存调优 | `Files/etc/uci-defaults/97-ram-tune` + `Files/etc/init.d/homeproxy-ram` | 首启一次：dnsmasq `cachesize=8192`、`log_size=128`、sysctl 网络缓冲与 conntrack；每boot：homeproxy 看板软链到 `/tmp/homeproxy-dashboard` |

`IPv4-Default.sh` 在 `make defconfig` 之前执行，核心是让生成器跳过 IPv6 分支，并用首启脚本兜底清理：

```sh
# 由 Scripts/Settings.sh 在源码根目录 ./wrt 下调用
bash "$GITHUB_WORKSPACE/Scripts/IPv4-Default.sh"

# 可选开关，在 workflow 的 env 中设置即可，无需改脚本：
#   IPV6_HARD_DISABLE=1  连内核 IPv6 栈一起禁用（net.ipv6.conf.*.disable_ipv6=1）
#   IPV6_FILTER_AAAA=1   让 dnsmasq 不返回 AAAA 记录
```

## 构建加速与诊断

`WRT-CORE` 除常规编译流程外，还有几处针对 CI 的处理：

- **缓存**：`actions/cache` 按 `wrt-<source>-<branch>-<target>-<commit>` 缓存 `.ccache` 与 `staging_dir/host*`、`tool*`；命中后 touch stamp 文件避免重编。`cache-rollover` job 在新缓存生成后删除同前缀的旧代缓存。
- **复用 runner 工具链**：`.github/scripts/prepare-build-host.sh` 复用宿主 Go 与 LLVM(BPF)；`prepare-rust.sh` + `rust-prebuilt.mk` 用 runner 的 Rust 目标三元组绕过源码自举；`prepare-i2c-tools.sh` 仅在选中 `python3-smbus` 时构建 Python 绑定。
- **失败回退**：`make -j$(nproc)` 失败后自动改跑 `make -j1 V=s` 便于定位错误。
- **构建报告**：`collect-build-reports.sh` 汇总 `.config`、feeds 列表、编译耗时 Top 30、ccache 统计与 Go / Python / Rust 版本，上传为 `build-reports-*` artifact，保留 7 天。

## 目录结构

```
.github/workflows/            QCA-ALL.yml / WRT-CORE.yml / Auto-Clean.yml / Cache-Clean.yml
.github/workflows/disabled/    AIROHA-ALL / MTK-ALL / OWRT-ALL / QCB-ALL / WRT-TEST（停用）
.github/scripts/              宿主 Go / LLVM / Rust / i2c-tools 准备，构建报告收集
Config/                       IPQ60XX-WIFI-YES.txt（设备）/ GENERAL.txt（公共）/ disabled/
Files/                        etc/init.d（mtd19-data）/ etc/uci-defaults（99-mtd19-data）
Scripts/                      Packages.sh（插件源）/ Settings.sh（默认设置）
                              Handles.sh（补丁）/ IPv4-Default.sh（纯 IPv4）
```

## 使用方法

1. Fork 仓库（workflow 未设置 owner/sender 校验，Fork 后可直接运行）。
2. 进入 **Actions** → **QCA-ALL** → **Run workflow**；需要临时加包时填 `PACKAGE`，只想核对配置时勾 `TEST`。
3. 编译完成后在 **Releases** 下载对应文件：升级用 `*squashfs-sysupgrade.bin`，首次刷入用 `*squashfs-factory.ubi`。同批的 `Config-*.txt` 与 `.manifest` 可用于复核。
4. Release tag 格式为 `<CONFIG>-<INFO>-<BRANCH>-<DATE>`，例如 `IPQ60XX-WIFI-YES-VIKINGYFY-owrt-26.11.14-19.06.52`。
5. 首次登录 `http://192.168.100.1`，用户名 `root`、密码为空，请立即设置密码并按需修改 Wi-Fi。
6. 大分区机型刷完后自检：`df -h /overlay`（应约 23 MiB）、`df -h /mnt/data`（应约 36.6 MiB）、`logread | grep mtd-data`（可见挂载日志）。

> 若要恢复其他平台：把 `.github/workflows/disabled/` 下对应 yml 移回 `.github/workflows/`，把 `Config/disabled/` 下对应 txt 移回 `Config/`，再核对 `QCA-ALL.yml` 风格的矩阵配置与 `WRT-CORE` 的 `CONFIG_TARGET_*` 解析结果。自用配置按本人设备定制，换设备或换上游分支前请同步检查 `WRT_IP`、`WRT_THEME`、`WRT_SSID` 与脚本里的 sed 目标是否仍匹配上游。

## U-Boot 与分区布局

* **分区大小只由 mibib（`mtd1`）里的 SMEM 表决定，U-Boot 的 `.bin` 不带分区信息。** 换 U-Boot 不会改变 rootfs / overlay 的大小；想改分区必须同时改 mibib。
* 本机现状：coolsnowwolf（大雕）「不死 uboot + 大分区」一套 —— `mibib.bin` 刷 `mtd1`、`uboot.bin` 刷 `mtd7`，得到 rootfs 72 MiB + overlay 36.6 MiB 的布局。
* 另一套可选：[uBootKit](https://github.com/chenxin527/uboot-qsdk12.5-build)（开源，高通 QSDK 12.5 `u-boot-2016` 二次开发，覆盖 ipq50xx / ipq53xx / ipq60xx / ipq807x 二十多个机型），产物只有一个 `uboot-ipq60xx-redmi_ax5-*.bin`（约 0.62 MiB），**只覆盖 appsbl（`mtd7`），不含 mibib**。

| 维度 | 大雕不死 uboot + 大分区 | chenxin527 uBootKit |
| --- | --- | --- |
| 来源 | 闭源收费包（面包多），单机型定制 | 开源 GPL，源码可编译，GitHub Actions 自动出包 |
| 提供文件 | `uboot.bin` + `mibib.bin` 两件 | 只有 `uboot.bin`，只写 `mtd7` |
| 分区 | 自带 mibib，改成大分区（72 + 36.6 MiB） | 沿用现有 mibib / SMEM 表，不改分区；9008 模式下有 MIBIB 自动重载 |
| 进 Web | 断电按住 Reset 通电 | 任意键按住通电（LED 闪 3 次后常亮）、`failsafe` 环境变量、[uBootEnter](https://github.com/chenxin527/uBootEnter) 中断、9008 自动进、`bootipq` 失败自动进、TTL 手敲 `httpd` |
| 网络 | 需手动把电脑网卡设到 192.168.1.x | 内置 DHCP 自动分配，并过滤上级路由的 OFFER / ACK 防干扰；进 Web 后可改后台 IP |
| 界面 | 简易恢复页 | Argon 风格、移动端适配、httpd_debug 日志、传输进度与速率、网页终端 |
| 可刷固件 | Web 上传 factory `.ubi` | NAND 只支持 factory（`.ubi`），**不支持 sysupgrade**；eMMC 支持 factory + sysupgrade；另有 GL.iNet 官方、部分 ASUSWRT、纯 NOR |
| 额外 | — | 开机打印机型与 config_name、LED 闪烁提示、修 AX5 京东云版网口 / LED |

> **风险提示**：两套 U-Boot 占的是同一个分区（appsbl / `mtd7`），刷写途中断电两套都没了，只能走 9008（EDL）救砖。uBootKit 的 README 没有给出首次刷入的具体命令，稳妥做法是用现有不死 uboot 的网页上传其 `.bin`，不要照抄来历不明的 `mtd write` 命令。该机改过 1G 内存，属于非原厂配置，刷前确认型号是 `redmi_ax5` 而不是 `redmi_ax5-jdcloud`。

## 相关资源

| 类型 | 链接 |
| --- | --- |
| 交流群 | [IPQ 技术讨论群](https://qm.qq.com/q/v7nMhzB4oU) |
| 中转站 | [LiBwrt-Ai](https://api.zipimg.cn/register?aff=FFPS3UMJ8HJD) |
| 本地编译工具 | [VIKINGYFY/OWRT-Tools](https://github.com/VIKINGYFY/OWRT-Tools.git) |
| 自用修改版插件 | [VIKINGYFY/packages](https://github.com/VIKINGYFY/packages.git) |
| ImmortalWrt 官方版 | [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt.git) |
| ImmortalWrt 自用版 | [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt.git) |
| U-Boot 高通（沉心） | [chenxin527/uboot-qsdk12.5-build](https://github.com/chenxin527/uboot-qsdk12.5-build.git) |
| U-Boot 高通（小猪） | [1980490718/u-boot-2016](https://github.com/1980490718/u-boot-2016.git) |
| U-Boot 联发科（全新版） | [VIKINGYFY/UBOOT-CI Releases](https://github.com/VIKINGYFY/UBOOT-CI/releases) |
| U-Boot 联发科（官方版） | [drive.wrt.moe/uboot/mediatek](https://drive.wrt.moe/uboot/mediatek) |

## Star History

上游 [vikingyfy/openwrt-ci](https://github.com/vikingyfy/openwrt-ci) 的 Star 走势：

<a href="https://www.star-history.com/?repos=vikingyfy%2Fopenwrt-ci&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=vikingyfy/openwrt-ci&type=date&legend=top-left" />
 </picture>
</a>

## 许可证

[MIT](LICENSE)，Copyright (c) 2026 VIKINGYFY（上游项目）。
