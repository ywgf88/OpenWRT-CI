#!/bin/bash
# SPDX-License-Identifier: MIT
# 让编译出的固件默认走 IPv4（关闭 IPv6 的自动配置与地址下发）
#
# 由 Scripts/Settings.sh 在源码根目录（./wrt）下调用，必须在 make defconfig 之前执行。
#
# 默认行为（不改内核，可后续在 LuCI 里重新开回 IPv6）：
#   1. /etc/config/network 不再生成 ula_prefix、lan 不再 ip6assign、wan 不再建 wan6(dhcpv6)
#   2. /etc/config/dhcp 的 lan 段关闭 ra / dhcpv6 / ndp，不再向终端下发 IPv6
#   3. /etc/config/firewall 打上 disable_ipv6 1
#   4. 额外投放一个 uci-defaults 脚本，首启/恢复出厂时兜底清理已存在的 IPv6 配置
#
# 可选开关（在 workflow 的 env 里设置即可，无需改本文件）：
#   IPV6_HARD_DISABLE=1  连内核 IPv6 栈一起禁用（net.ipv6.conf.*.disable_ipv6=1，最彻底）
#   IPV6_FILTER_AAAA=1   只让 dnsmasq 不返回 AAAA 记录（双栈环境强制解析走 IPv4）

IPV6_HARD_DISABLE="${IPV6_HARD_DISABLE:-0}"
IPV6_FILTER_AAAA="${IPV6_FILTER_AAAA:-0}"

log() { echo "[ipv4-default] $*"; }

# ---------- 1. 默认 network 配置生成逻辑 ----------
# immortalwrt 的 config_generate 用 [ -e /proc/sys/net/ipv6 ] 判断是否启用 IPv6，
# 而这个判断在编译机上恒为真，于是固件首启就写入 ula_prefix / ip6assign / wan6。
# 全部改成 false，等于让生成器彻底跳过 IPv6 分支。
CFG_GENERATE="package/base-files/files/bin/config_generate"
if [ -f "$CFG_GENERATE" ]; then
	sed -i 's#\[ -e /proc/sys/net/ipv6 \]#false#g' "$CFG_GENERATE"
	log "config_generate: 已关闭 ula_prefix / ip6assign / wan6(dhcpv6)"
else
	log "警告: 未找到 $CFG_GENERATE，跳过 network 生成逻辑修改"
fi

# ---------- 2. 默认 dhcp 配置（RA / DHCPv6 / NDP 下发） ----------
DHCP_CONF="package/network/services/dnsmasq/files/dhcp.conf"
if [ -f "$DHCP_CONF" ]; then
	sed -i -E "s/^([[:space:]]*option[[:space:]]+ra[[:space:]]+).*/\1disabled/" "$DHCP_CONF"
	sed -i -E "s/^([[:space:]]*option[[:space:]]+dhcpv6[[:space:]]+).*/\1disabled/" "$DHCP_CONF"
	# odhcpd 读的是同一个文件，补一个 ndp disabled
	if ! grep -qE "^[[:space:]]*option[[:space:]]+ndp[[:space:]]" "$DHCP_CONF"; then
		sed -i -E "/^[[:space:]]*config[[:space:]]+dhcp[[:space:]]+lan$/a\\\toption ndp\t\tdisabled" "$DHCP_CONF"
	fi
	if [ "$IPV6_FILTER_AAAA" = "1" ]; then
		sed -i -E "s/^([[:space:]]*option[[:space:]]+filter_aaaa[[:space:]]+).*/\11/" "$DHCP_CONF"
	fi
	log "dhcp.conf: ra / dhcpv6 / ndp 已置为 disabled${IPV6_FILTER_AAAA:+ (filter_aaaa=$IPV6_FILTER_AAAA)}"
else
	log "警告: 未找到 $DHCP_CONF，跳过 dhcp 默认配置修改"
fi

# ---------- 3. 防火墙不再生成 IPv6 规则 ----------
FW_CONF="package/network/config/firewall/files/firewall.config"
if [ -f "$FW_CONF" ]; then
	if grep -qE "^[[:space:]]*#?[[:space:]]*option[[:space:]]+disable_ipv6" "$FW_CONF"; then
		sed -i -E "/disable ipv6 rules/d" "$FW_CONF"
		sed -i -E "s/^[[:space:]]*#?[[:space:]]*(option[[:space:]]+disable_ipv6).*/\t\1 1/" "$FW_CONF"
	else
		sed -i "0,/^config defaults/s//config defaults\n\toption disable_ipv6\t1/" "$FW_CONF"
	fi
	log "firewall.config: disable_ipv6 已开启"
else
	log "警告: 未找到 $FW_CONF，跳过防火墙默认配置修改"
fi

# ---------- 4. 首启兜底：清理已生成的 IPv6 配置 ----------
# config_generate 只在 /etc/config/network 为空时生成配置；
# 这个脚本在每次首启/恢复出厂时都会跑一遍，保证现场一定没有 IPv6 上行。
UCI_DEFAULTS_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS_DIR"
cat > "$UCI_DEFAULTS_DIR/99-ipv4-default" <<'EOF'
#!/bin/sh
# 默认使用 IPv4：清理 IPv6 上行与地址下发
[ -f /etc/config/network ] || exit 0

# 全局 ULA 前缀
uci -q delete network.globals.ula_prefix

# LAN：撤销 IPv6 地址分配
if uci -q get network.lan >/dev/null; then
	uci -q set network.lan.ipv6='0'
	uci -q delete network.lan.ip6assign
	uci -q delete network.lan.ip6hint
	uci -q delete network.lan.ip6prefix
	uci -q delete network.lan.ip6class
	uci -q delete network.lan.ip6ifaceid
	uci -q delete network.lan.ip6weight
	uci -q delete network.lan.extendprefix
fi

# WAN：关闭 IPv6 请求并移除 wan6
if uci -q get network.wan >/dev/null; then
	uci -q set network.wan.ipv6='0'
	uci -q delete network.wan.ip6assign
fi
uci -q delete network.wan6

# 任何残留的纯 IPv6 接口一并删除
# 匿名段（@interface[0] 这类）按索引倒序删，避免删除后索引位移导致删错
ipv6_ifaces=$(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.=]*\)\.proto='\(dhcpv6\|static6\|6in4\|6to4\|6rd\|dslite\|map\)'$/\1/p")
for iface in $(echo "$ipv6_ifaces" | grep '^@' | awk -F'[][]' '{print $2"\t"$0}' | sort -rn | cut -f2); do
	uci -q delete network."$iface"
done
for iface in $(echo "$ipv6_ifaces" | grep -v '^@' | grep .); do
	uci -q delete network."$iface"
done

# DHCP/RA/NDP 不再下发 IPv6
for sec in $(uci -q show dhcp 2>/dev/null | sed -n "s/^dhcp\.\([^.=]*\)=dhcp$/\1/p"); do
	uci -q set dhcp."$sec".ra='disabled'
	uci -q set dhcp."$sec".dhcpv6='disabled'
	uci -q set dhcp."$sec".ndp='disabled'
	uci -q delete dhcp."$sec".ra_flags
	uci -q delete dhcp."$sec".ra_slaac
done

# 防火墙不生成 IPv6 规则
uci -q get firewall.@defaults[0] >/dev/null && uci -q set firewall.@defaults[0].disable_ipv6='1'

uci -q commit network
uci -q commit dhcp
uci -q commit firewall

exit 0
EOF
chmod +x "$UCI_DEFAULTS_DIR/99-ipv4-default"
log "已投放 uci-defaults/99-ipv4-default（首启兜底清理）"

# ---------- 5. 可选：连内核 IPv6 栈一起关掉 ----------
SYSCTL_DIR="package/base-files/files/etc/sysctl.d"
if [ "$IPV6_HARD_DISABLE" = "1" ]; then
	mkdir -p "$SYSCTL_DIR"
	cat > "$SYSCTL_DIR/11-disable-ipv6.conf" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
	log "已写入 sysctl.d/11-disable-ipv6.conf（内核 IPv6 已彻底禁用）"
elif [ -f "$SYSCTL_DIR/11-disable-ipv6.conf" ]; then
	rm -f "$SYSCTL_DIR/11-disable-ipv6.conf"
	log "已移除旧的 sysctl IPv6 禁用文件（软模式）"
fi

log "完成：本固件默认 IPv4，IPv6 需在 LuCI 里手动开启"
