#!/bin/bash
# =============================================================
# apply-plugins-menu.sh —— 把 Actions 菜单里的插件勾选，翻译成 .config + diy 开关改动
# 由工作流步骤 "Apply plugin menu" 调用
#
# 输入：环境变量 PLUGIN_<别名>（来自 workflow_dispatch 的 choice，值为 'y'/'n'）
# 输出：直接改写 configs/<profile>.config 和 diy-part1-menu.sh；写一份摘要到 GITHUB_STEP_SUMMARY
#
# 菜单变量名映射表见下面 PLUGINS 第 5 列。workflow 里用 env: 把 inputs.* 转成的
# 同名环境变量传进来。缺省一律视为 'n'。
# 语义：y = 强制编进固件（写 =y + 打开 diy 开关）；
#       n = 保持该机型配置原样（不写 is not set，不动 diy 开关）——这样不会误删
#           通用配置 an7581.config 里默认开启的插件，profile=all 也安全。
# 注意：本脚本只动"可选插件"，绝不碰 PON/FTTR/WiFi/NPU 等固件核心包。
# =============================================================
set -eo pipefail

WORKSPACE="${GITHUB_WORKSPACE:-$PWD}"
PROFILE="${PROFILE:-}"
SOC="${SOC:-}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
info(){ echo "[apply-plugins] $*"; }

# pkg | diy开关(空=feeds/基座现成) | 中文名 | 菜单变量名后缀 | 依赖包(空格分隔)
PLUGINS=(
  "luci-app-passwall|ADD_PASSWALL|PassWall 代理|PASSWALL|xray-core sing-box"
  "luci-app-openclash|ADD_OPENCLASH|OpenClash|OPENCLASH|"
  "luci-app-smartdns|ADD_SMARTDNS|SmartDNS|SMARTDNS|"
  "luci-app-mosdns|ADD_MOSDNS|MosDNS|MOSDNS|"
  "luci-app-tailscale|ADD_TAILSCALE|Tailscale 组网|TAILSCALE|"
  "luci-app-easytier|ADD_EASYTIER|EasyTier 组网|EASYTIER|easytier"
  "luci-app-upnp||UPnP|UPNP|"
  "luci-app-lucky|ADD_LUCKY|Lucky DDNS|LUCKY|"
  "luci-app-openlist2|ADD_OPENLIST|OpenList 网盘|OPENLIST|"
  "luci-app-watchdog|ADD_WATCHDOG|看门狗|WATCHDOG|"
  "luci-app-taskplan|ADD_TASKPLAN|定时任务|TASKPLAN|"
  "luci-app-owq-wol|ADD_OWQ_WOL|网络唤醒|WOL|"
  "luci-app-poweroffdevice|ADD_POWEROFF|关机按钮|POWEROFF|"
  "luci-app-oaf|ADD_OAF|应用过滤OAF|OAF|"
  "luci-app-argon-config|ADD_ARGON_CONFIG|Argon设置页|ARGON|"
  "luci-theme-fluent|ADD_FLUENT|Fluent主题|FLUENT|"
  "luci-proto-wireguard||WireGuard VPN|WIREGUARD|wireguard-tools rpcd-mod-wireguard resolveip"
  "curl||curl命令行|CURL|"
  "nano||nano编辑器|NANO|"
  "htop||htop监控|HTOP|"
  "ttyd||网页终端|TTYD|"
)

menu_on(){
  local key="PLUGIN_$1" v
  v="${!key:-n}"
  [ "$v" = "y" ] && return 0 || return 1
}

# ---------- 定位目标 config ----------
if [ "$PROFILE" = "all" ]; then CFG="$WORKSPACE/configs/${SOC}.config"; else CFG="$WORKSPACE/configs/${PROFILE}.config"; fi
DIY="$WORKSPACE/diy-part1-menu.sh"
[ -f "$CFG" ] || { echo "::error::找不到配置 $CFG"; exit 1; }
[ -f "$DIY" ] || { echo "::error::找不到 diy-part1-menu.sh"; exit 1; }
cp "$CFG" "$CFG.bak"; cp "$DIY" "$DIY.bak"
info "目标配置: $CFG"

ENABLED=()

set_diy_switch(){ # $1=开关名 $2=true/false
  local sw="$1" val="$2"
  if grep -qE "^: \"\\\$\{${sw}:=" "$DIY"; then
    sed -i -E "s|^: \"\\\$\{${sw}:=[a-z]+\}\"|: \"\${${sw}:=${val}}\"|" "$DIY"
  elif grep -qE "^${sw}=" "$DIY"; then
    sed -i -E "s|^${sw}=.*|${sw}=${val}|" "$DIY"
  else
    echo ": \"\${${sw}:=${val}}\"" >> "$DIY"
  fi
}

for entry in "${PLUGINS[@]}"; do
  IFS='|' read -r pkg sw cn alias deps <<< "$entry"
  syms="$pkg${deps:+ $deps}"
  if menu_on "$alias"; then
    # y：清掉旧行（含注释）后写 =y，并打开 diy 开关
    for s in $syms; do
      sed -i "/^CONFIG_PACKAGE_${s}=/d; /^# CONFIG_PACKAGE_${s} is not set/d; /^# *CONFIG_PACKAGE_${s}=/d" "$CFG"
      echo "CONFIG_PACKAGE_${s}=y" >> "$CFG"
    done
    if [ -n "$sw" ]; then set_diy_switch "$sw" true; fi
    ENABLED+=("$cn（$pkg）")
  fi
  # n：什么都不做，保持机型配置原样（不误删通用配置里默认开启的插件）
done

{
  echo "## 🧩 本次固件插件定制"
  echo ""
  echo "**机型**：$PROFILE（$SOC）　**配置**：$(basename "$CFG")"
  echo ""
  echo "### ✅ 本次额外加入固件"
  if [ ${#ENABLED[@]} -gt 0 ]; then printf -- '- %s\n' "${ENABLED[@]}"; else echo '- （没有勾选额外插件，保持机型默认清单）'; fi
  echo ""
  echo "> 未勾选的插件保持该机型配置原样，不会误删默认插件。依赖内核/工具由编译系统按 DEPENDS 自动带上；原文件已备份为 \`.bak\`。"
} >> "$SUMMARY"

info "完成：加入 ${#ENABLED[@]} 项（其余保持机型默认）"
