#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 - 环境自检与一键安装
# 用法: bash setup_env.sh [--install]
#   --install  发现缺失时自动尝试安装（venv / Python 包）
#
# v2.2-winfix（2026-11-12 Windows 真机验证修复）:
#   ① 创建 venv / 装包后【重新探测】CLI 与 pip。原版在脚本开头把 LX_CLI / LX_PIP
#      快照成变量，Windows 上 --install 会一直拿着 bin/pip 去装包 → 必失败且静默。
#   ② CLI 就绪判定改为「实际跑一次 version」，不再只看 -x ——
#      Windows WDAC / Device Guard 会拦未签名的 pip launcher，-x 完全测不出来。
#   ③ --install 失败显性化：计入 FAIL 并打印原因与 pip 路径。
#   ④ Windows 专项：Scripts/ 解释器、pymupdf、QQ 浏览器安装路径补充。
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_platform.sh"
VENV="$LX_VENV"
OS="$LX_OS"
PASS=0; FAIL=0

say_ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
say_bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
say_warn() { echo "  ⚠️  $1"; }

# Windows venv 的 Scripts/ 目录在「创建之后」才存在，必须重新 source 一次平台层，
# 否则 LX_CLI / LX_PIP 会永远停在 venv 不存在时的 bin/ 回落值。
refresh_platform() {
  source "$SCRIPT_DIR/lib_platform.sh"
  VENV="$LX_VENV"
  CLI="$LX_CLI"
}
refresh_platform

# -x 只看权限位；被 WDAC 拦截的 exe 依然 -x 为真，必须真跑一次才知道。
cli_runnable() {
  [ -x "${1:-}" ] || return 1
  "$1" version >/dev/null 2>&1
}

echo "=========================================="
echo " 理杏仁下载 · 环境自检"
echo " 系统: $OS   环境: $VENV"
echo "=========================================="

# ---- 1. Python ----
echo "[1/6] Python"
if command -v python3 >/dev/null 2>&1; then
  PV=$(python3 --version 2>&1 | awk '{print $2}')
  MAJOR=$(echo "$PV" | cut -d. -f1); MINOR=$(echo "$PV" | cut -d. -f2)
  if [ "$MAJOR" -ge 3 ] && [ "$MINOR" -ge 9 ]; then
    say_ok "python3 $PV"
  else
    say_bad "python3 $PV 版本过低，需 ≥ 3.9"
  fi
else
  say_bad "未找到 python3（Windows: 装 Python 并勾选 Add Python to PATH；macOS: brew install python@3.11）"
fi

# ---- 2. venv ----
echo "[2/6] 虚拟环境"
if [ -f "$VENV/pyvenv.cfg" ]; then
  say_ok "venv 已存在"
  refresh_platform
else
  say_bad "venv 不存在"
  echo "       → 执行: python3 -m venv $VENV"
  if [[ "${1:-}" == "--install" ]]; then
    echo "       → 正在自动创建…"
    if mkdir -p "$(dirname "$VENV")" && python3 -m venv "$(lx_native_path "$VENV")"; then
      echo "       ✅ 已创建"
      refresh_platform   # ← Windows 关键：Scripts/ 结构此刻才出现
    else
      say_bad "venv 自动创建失败"
    fi
  fi
fi

# ---- 3. qqbrowser-skill CLI ----
echo "[3/6] qqbrowser-skill CLI"
refresh_platform
if cli_runnable "$CLI"; then
  say_ok "CLI 就位且可执行: $CLI"
elif [ -x "$CLI" ]; then
  say_bad "CLI 存在但无法执行（Windows WDAC / Device Guard 会拦未签名 pip launcher）: $CLI"
  echo "       → 修复: 用受信任的 python.exe 驱动 x5use.server:main"
  echo "         检查: bash $SCRIPT_DIR/qqbrowser_skill_cli.sh version"
else
  say_bad "CLI 未安装"
  echo "       → 执行: $LX_PIP install qqbrowser-skill"
  if [[ "${1:-}" == "--install" ]] && [ -f "$VENV/pyvenv.cfg" ]; then
    echo "       → 正在自动安装…"
    if "$LX_PIP" install -q qqbrowser-skill; then
      echo "       ✅ 已安装"
      refresh_platform
      # Windows 专项：--install 顺带装 pymupdf（年报内容校验的硬依赖）
      if [ "$OS" = "windows" ]; then
        _winpy="$VENV/Scripts/python.exe"
        if [ -x "$_winpy" ] && ! "$_winpy" -c 'import pymupdf' >/dev/null 2>&1; then
          echo "       → 正在安装 pymupdf（年报内容校验依赖）…"
          "$_winpy" -m pip install -q pymupdf && echo "       ✅ pymupdf 已安装" \
            || say_warn "pymupdf 安装失败，年报 PDF 可能被内容校验拒收"
        fi
      fi
      refresh_platform
    else
      say_bad "qqbrowser-skill 自动安装失败（pip: ${LX_PIP}）"
    fi
  fi
fi

# ---- 4. 浏览器 ----
echo "[4/6] 浏览器"
BROWSER_FOUND=0
case "$LX_OS" in
  mac)
    if [ -d "/Applications/QQBrowser.app" ]; then say_ok "QQ 浏览器已安装（macOS）"; BROWSER_FOUND=1; fi
    [ -d "/Applications/Google Chrome.app" ] && say_ok "Chrome 已安装（备选通道）"
    ;;
  linux)
    command -v qqbrowser >/dev/null 2>&1 && { say_ok "QQ 浏览器已安装（Linux）"; BROWSER_FOUND=1; }
    command -v google-chrome >/dev/null 2>&1 && say_ok "Chrome 已安装（备选通道）"
    ;;
  windows)
    # Windows 版 QQ 浏览器常见落地位置：用户级 / 机器级 / 带版本号子目录
    _qq_dirs=(
      "$(lx_slash "${LOCALAPPDATA:-}")/Tencent/QQBrowser"
      "$(lx_slash "${LOCALAPPDATA:-}")/Tencent/QQBrowser/Application"
      "$(lx_slash "${USERPROFILE:-}")/AppData/Local/Tencent/QQBrowser"
      "/c/Program Files (x86)/Tencent/QQBrowser"
      "/c/Program Files/Tencent/QQBrowser"
      "/d/Program Files (x86)/Tencent/QQBrowser"
    )
    for _d in "${_qq_dirs[@]}"; do
      [ -d "$_d" ] && { say_ok "QQ 浏览器已安装（Windows）: $_d"; BROWSER_FOUND=1; break; }
    done
    if [ "$BROWSER_FOUND" -eq 0 ] && command -v QQBrowser.exe >/dev/null 2>&1; then
      say_ok "QQ 浏览器在 PATH 中"; BROWSER_FOUND=1
    fi
    ;;
esac
[ "$BROWSER_FOUND" -eq 0 ] && say_bad "未找到 QQ 浏览器 → 下载 https://browser.qq.com/ （Linux 请走 Playwright 备选通道）"

# ---- 5. 守护进程 ----
echo "[5/6] 守护进程"
refresh_platform
if cli_runnable "$CLI"; then
  ST=$("$CLI" status 2>/dev/null)
  if echo "$ST" | grep -q "Daemon is running"; then
    say_ok "守护进程运行中"
    CLIENTS=$(echo "$ST" | grep -oE "Connected clients: [0-9]+" | grep -oE "[0-9]+")
    if [ "${CLIENTS:-0}" -ge 1 ]; then
      say_ok "浏览器已连接（clients=${CLIENTS}）"
    else
      say_warn "浏览器未连接（clients=0）→ 关闭浏览器重开，或重新执行: $CLI serve --daemon"
    fi
  else
    say_bad "守护进程未运行 → 执行: $CLI serve --daemon"
    if [[ "${1:-}" == "--install" ]]; then
      echo "       → 正在启动…"
      "$CLI" serve --daemon >/dev/null 2>&1 && sleep 2 && echo "       ✅ 已启动" \
        || say_warn "守护进程启动失败（检查端口 8765/8766 是否被占）"
    fi
  fi
else
  say_bad "CLI 不可执行，跳过守护进程检查（先修复 [3/6]）"
fi

# ---- 6. 登录态（凭证 + 自动登录）----
echo "[6/6] 理杏仁登录态"
echo "      ℹ️  凭证: ~/.config/lixinger-download/creds.json (600, 已 gitignore)"
echo "         下载脚本开会话前自动调用 scripts/lixinger_login.sh，未登录时自动填表提交。"
echo "      ⛔ 切勿因未登录就换数据源(东财/巨潮/上交所/新浪均不可取, 实测全部失败)。"
echo "      自检: bash scripts/lixinger_login.sh --check  (输出 当前状态: IN 即正常)"
if [ -f "$LX_CREDS" ]; then
  say_ok "凭证文件存在: $LX_CREDS"
else
  say_warn "缺凭证文件: ${LX_CREDS}（自动登录不可用，只能依赖浏览器残留登录态）"
fi

# ---- Windows 专项（不计 FAIL，只提示）----
if [ "$LX_OS" = "windows" ]; then
  echo
  echo "[Windows 专项]"
  _wp=""
  for _c in "$VENV/Scripts/python.exe" "$VENV/Scripts/python" "$VENV/bin/python3"; do
    [ -x "$_c" ] && { _wp="$_c"; break; }
  done
  if [ -n "$_wp" ]; then
    if "$_wp" -c 'import pymupdf' >/dev/null 2>&1; then
      say_ok "venv 解释器带 pymupdf（年报内容校验依赖）: $_wp"
    else
      say_warn "venv 缺 pymupdf → 年报 PDF 会被内容校验拒收；装: \"$_wp\" -m pip install pymupdf"
    fi
  else
    say_warn "venv 解释器未找到，跳过 pymupdf 检查"
  fi
  echo "      ℹ️  chmod 600 不映射 NTFS ACL，凭证请另确认仅当前用户可读"
  echo "      ℹ️  .sh 只能在 Git Bash / MSYS2 / WSL 执行；PowerShell 不支持"
fi

echo "=========================================="
echo " 结果: ✅ $PASS 项通过, ❌ $FAIL 项缺失"
if [ "$FAIL" -eq 0 ]; then
  echo " 🎉 环境就绪，可以开始下载"
else
  echo " ⚠️  请修复缺失项后重试（加 --install 可自动安装 Python 依赖）"
fi
echo "=========================================="
exit "$FAIL"
