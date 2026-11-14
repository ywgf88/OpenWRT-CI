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

> `WRT_PW` 仅为 Release 文案里的提示字段，修改它**不会**改变固件登录密码；密码始终需要首次登录后自行设置。产物按平台打包，刷机前请核对设备型号、分区布局与 factory/sysupgrade 用途。

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
| 代理 / 分流 | `luci-app-homeproxy`、`sing-box`（在设备 config 中启用）、`fullconenat-sonic`、`luci-app-natmapt`、`stuntman-client` |
| 系统 / 运维 | `luci-app-autoreboot`、`luci-app-gecoosac`、`luci-app-upnp`、`luci-app-wolultra`、`htop`、`iperf3`、`curl`、`ip-full`、`lsblk`、`nand-utils`、`xz-utils`、`openssh-sftp-server` |
| 内核模块 | `kmod-nft-*`（core / nat / offload / tproxy / queue / socket / fib 等）、`kmod-wireguard`、`kmod-tun`、`kmod-mtd-rw`、`kmod-dsa`、`kmod-inet-diag` |
| 构建开关 | `CONFIG_CCACHE=y`、`CONFIG_DEVEL=y`、`CONFIG_TARGET_MULTI_PROFILE=y`、`CONFIG_TARGET_PER_DEVICE_ROOTFS=y`；关闭 `luci-app-attendedsysupgrade`、`luci-app-wol` 与 `video` / `pon_*` feed |

**最近一次 Release 实际装入的 LuCI 应用**（取自 manifest，随上游变动，以 Release 说明的「插件列表」为准）

`luci-app-autoreboot` · `firewall` · `fullconenat-sonic` · `gecoosac` · `homeproxy` · `mini-diskmanager` · `natmapt` · `package-manager` · `partexp` · `qca-ppe-qos` · `router-tool` · `samba4` · `upnp` · `vantage` · `wolultra`，主题 `luci-theme-vantage`。

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
Scripts/                      Packages.sh（插件源）/ Settings.sh（默认设置）
                              Handles.sh（补丁）/ IPv4-Default.sh（纯 IPv4）
```

## 使用方法

1. Fork 仓库（workflow 未设置 owner/sender 校验，Fork 后可直接运行）。
2. 进入 **Actions** → **QCA-ALL** → **Run workflow**；需要临时加包时填 `PACKAGE`，只想核对配置时勾 `TEST`。
3. 编译完成后在 **Releases** 下载对应文件：升级用 `*squashfs-sysupgrade.bin`，首次刷入用 `*squashfs-factory.ubi`。同批的 `Config-*.txt` 与 `.manifest` 可用于复核。
4. Release tag 格式为 `<CONFIG>-<INFO>-<BRANCH>-<DATE>`，例如 `IPQ60XX-WIFI-YES-VIKINGYFY-owrt-26.11.14-19.06.52`。
5. 首次登录 `http://192.168.100.1`，用户名 `root`、密码为空，请立即设置密码并按需修改 Wi-Fi。

> 若要恢复其他平台：把 `.github/workflows/disabled/` 下对应 yml 移回 `.github/workflows/`，把 `Config/disabled/` 下对应 txt 移回 `Config/`，再核对 `QCA-ALL.yml` 风格的矩阵配置与 `WRT-CORE` 的 `CONFIG_TARGET_*` 解析结果。自用配置按本人设备定制，换设备或换上游分支前请同步检查 `WRT_IP`、`WRT_THEME`、`WRT_SSID` 与脚本里的 sed 目标是否仍匹配上游。

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
