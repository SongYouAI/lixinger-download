#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 - 环境自检与一键安装
# 用法: bash setup_env.sh [--install]
#   --install  发现缺失时自动尝试安装（Python 包）
# ============================================================
set -uo pipefail

VENV="${LIXINGER_VENV:-$HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl}"
CLI="$VENV/bin/qqbrowser-skill"
OS="$(uname -s)"
PASS=0; FAIL=0

say_ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
say_bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
say_warn() { echo "  ⚠️  $1"; }

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
  say_bad "未找到 python3（macOS: brew install python@3.11 / Ubuntu: apt install python3 python3-venv）"
fi

# ---- 2. venv ----
echo "[2/6] 虚拟环境"
if [ -d "$VENV" ]; then
  say_ok "venv 已存在"
else
  say_bad "venv 不存在"
  echo "       → 执行: python3 -m venv $VENV"
  if [[ "${1:-}" == "--install" ]]; then
    echo "       → 正在自动创建…"
    mkdir -p "$(dirname "$VENV")" && python3 -m venv "$VENV" && echo "       ✅ 已创建"
  fi
fi

# ---- 3. qqbrowser-skill CLI ----
echo "[3/6] qqbrowser-skill CLI"
if [ -x "$CLI" ]; then
  say_ok "CLI 就位: $CLI"
else
  say_bad "CLI 未安装"
  echo "       → 执行: $VENV/bin/pip install qqbrowser-skill"
  if [[ "${1:-}" == "--install" ]] && [ -d "$VENV" ]; then
    echo "       → 正在自动安装…"
    "$VENV/bin/pip" install -q qqbrowser-skill && echo "       ✅ 已安装"
  fi
fi

# ---- 4. 浏览器 ----
echo "[4/6] 浏览器"
BROWSER_FOUND=0
case "$OS" in
  Darwin)
    if [ -d "/Applications/QQBrowser.app" ]; then say_ok "QQ 浏览器已安装（macOS）"; BROWSER_FOUND=1; fi
    [ -d "/Applications/Google Chrome.app" ] && say_ok "Chrome 已安装（备选通道）"
    ;;
  Linux)
    command -v qqbrowser >/dev/null 2>&1 && { say_ok "QQ 浏览器已安装（Linux）"; BROWSER_FOUND=1; }
    command -v google-chrome >/dev/null 2>&1 && say_ok "Chrome 已安装（备选通道）"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    [ -d "/c/Program Files (x86)/Tencent/QQBrowser" ] && { say_ok "QQ 浏览器已安装（Windows）"; BROWSER_FOUND=1; }
    ;;
esac
[ "$BROWSER_FOUND" -eq 0 ] && say_bad "未找到 QQ 浏览器 → 下载 https://browser.qq.com/ （Linux 请走 Playwright 备选通道）"

# ---- 5. 守护进程 ----
echo "[5/6] 守护进程"
if [ -x "$CLI" ]; then
  ST=$("$CLI" status 2>/dev/null)
  if echo "$ST" | grep -q "Daemon is running"; then
    say_ok "守护进程运行中"
    CLIENTS=$(echo "$ST" | grep -oE "Connected clients: [0-9]+" | grep -oE "[0-9]+")
    if [ "${CLIENTS:-0}" -ge 1 ]; then
      say_ok "浏览器已连接（clients=$CLIENTS）"
    else
      say_warn "浏览器未连接（clients=0）→ 关闭浏览器重开，或重新执行: $CLI serve --daemon"
    fi
  else
    say_bad "守护进程未运行 → 执行: $CLI serve --daemon"
    if [[ "${1:-}" == "--install" ]]; then
      echo "       → 正在启动…"
      "$CLI" serve --daemon >/dev/null 2>&1 && sleep 2 && echo "       ✅ 已启动"
    fi
  fi
else
  say_bad "CLI 缺失，跳过守护进程检查"
fi

# ---- 6. 登录态 ----
echo "[6/6] 理杏仁登录态（需人工确认）"
echo "      请手动在浏览器打开 https://www.lixinger.com"
echo "      ✅ 若自动跳转到个人中心（/profile/center/...）→ 已登录"
echo "      ❌ 若停在登录页 → 请先手动登录一次"

echo "=========================================="
echo " 结果: ✅ $PASS 项通过, ❌ $FAIL 项缺失"
if [ "$FAIL" -eq 0 ]; then
  echo " 🎉 环境就绪，可以开始下载"
else
  echo " ⚠️  请修复缺失项后重试（加 --install 可自动安装 Python 依赖）"
fi
echo "=========================================="
exit "$FAIL"
