#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 · 平台抽象层（被所有脚本 source，必须先于其他 lib）
#
# 解决的问题（2026-11-10 阶段 1）：
#   ① Windows venv 的 CLI 在 Scripts/qqbrowser-skill.exe，不是 bin/
#   ② /tmp 在 Git Bash 里是 MSYS 虚拟路径，Windows 原生 Python 会解析成 C:\tmp\
#      → shell 写的文件 Python 读不到。统一用 LX_TMP（盘符+正斜杠，双方都认）
#   ③ Chrome/Edge Preferences、孤儿暂存目录在 macOS 用 ~/Library，Windows 用 %LOCALAPPDATA%
#   ④ --csv-dir 只认 /*，Windows 的 C:/... 会被拒
#
# 导出：LX_OS / LX_VENV / LX_CLI / LX_PIP / LX_TMP / LX_DOWNLOADS /
#       LX_CREDS / LX_BROWSER_DATA / LX_CACHE / LX_PY / IS_MAC
# 函数：lx_is_abs_path() / lx_native_path() / python3()（兼容转发）
#
# 支持终端：macOS bash、Linux bash、Windows Git Bash / MSYS2、WSL。
# PowerShell 不能执行 .sh，不在支持范围。
# ============================================================

_lx_uname="$(uname -s 2>/dev/null || printf 'unknown')"
case "$_lx_uname" in
  Darwin*)                LX_OS="mac" ;;
  Linux*)                 LX_OS="linux" ;;          # 含 WSL
  MINGW*|MSYS*|CYGWIN*)  LX_OS="windows" ;;
  *)                      LX_OS="unknown" ;;
esac

# 把 Windows 反斜杠路径转成正斜杠（C:/...）——bash 与 Windows 原生 Python 都认
lx_slash() {
  local p="${1:-}"
  p="${p//\\//}"
  p="${p%/}"
  printf '%s' "$p"
}

# 主目录：Windows 用 USERPROFILE（C:/... 形式），避免 $HOME 的 /c/... 传给原生 Python 后被解析错
if [ "$LX_OS" = "windows" ]; then
  LX_HOME="$(lx_slash "${USERPROFILE:-$HOME}")"
else
  LX_HOME="$HOME"
fi
LX_VENV="${LIXINGER_VENV:-$LX_HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl}"

# ---- CLI 探测 ----
# 🔴 Windows 专项（2026-11-12 真机实测）：
#   pip 生成的 $VENV/Scripts/qqbrowser-skill.exe 是【未签名】setuptools launcher，
#   启用 WDAC / Device Guard 的 Windows 会直接拒绝执行：
#     Git Bash → "Permission denied"(126)；cmd.exe → "已被组织 Device Guard 阻止"(199)。
#   原代码只会判断 -x（文件存在且可执行位为真），完全测不出这种"系统策略拦截"，
#   于是自检显示 CLI 就位，但所有 browser_* 调用全部失败。
#   解法：Windows 上优先用同目录 wrapper，以受信任的 python.exe 驱动 x5use.server:main。
#   仅当 venv 里确实装了 x5use 时才启用，避免"CLI 未安装却显示就位"。
_LX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LX_WRAPPER="$_LX_SCRIPT_DIR/qqbrowser_skill_cli.sh"
_LX_WIN_PY=""
for _c in "$LX_VENV/Scripts/python.exe" "$LX_VENV/Scripts/python"; do
  [ -x "$_c" ] && { _LX_WIN_PY="$_c"; break; }
done

if [ "$LX_OS" = "windows" ] && [ -f "$_LX_WRAPPER" ] && [ -n "$_LX_WIN_PY" ] \
   && "$_LX_WIN_PY" -c 'import x5use.server' >/dev/null 2>&1; then
  chmod +x "$_LX_WRAPPER" 2>/dev/null || true
  LX_CLI="$_LX_WRAPPER"
elif [ -x "$LX_VENV/Scripts/qqbrowser-skill.exe" ]; then
  LX_CLI="$LX_VENV/Scripts/qqbrowser-skill.exe"
elif [ -x "$LX_VENV/Scripts/qqbrowser-skill" ]; then
  LX_CLI="$LX_VENV/Scripts/qqbrowser-skill"
elif [ "$LX_OS" = "windows" ]; then
  # Windows venv 永远不会有 bin/；给一个"预期路径"便于诊断，而不是误导性的 bin/
  LX_CLI="$LX_VENV/Scripts/qqbrowser-skill.exe"
else
  LX_CLI="$LX_VENV/bin/qqbrowser-skill"
fi

# ---- pip 探测 ----
# 原代码在 venv 尚未创建时一律回落到 bin/pip，导致 setup_env.sh --install
# 在 Windows 上拿着 bin/pip 去装包 → "No such file or directory" 且静默失败。
if [ -x "$LX_VENV/Scripts/pip.exe" ]; then
  LX_PIP="$LX_VENV/Scripts/pip.exe"
elif [ -x "$LX_VENV/Scripts/pip" ]; then
  LX_PIP="$LX_VENV/Scripts/pip"
elif [ "$LX_OS" = "windows" ]; then
  LX_PIP="$LX_VENV/Scripts/pip.exe"
else
  LX_PIP="$LX_VENV/bin/pip"
fi

# 临时目录必须让 shell 与 Python 指向同一物理位置。
# Windows: 取 TEMP/TMP（或 Python tempfile），转 C:/... 形式；
# macOS/Linux: TMPDIR 或 /tmp，去掉尾斜杠。
if [ "$LX_OS" = "windows" ]; then
  _lx_t="${TEMP:-${TMP:-}}"
  if [ -z "$_lx_t" ]; then
    _lx_t="$(python3 -c 'import tempfile;print(tempfile.gettempdir())' 2>/dev/null || true)"
  fi
  LX_TMP="$(lx_slash "$_lx_t")"
  [ -n "$LX_TMP" ] || LX_TMP="C:/Windows/Temp"
else
  LX_TMP="$(lx_slash "${TMPDIR:-/tmp}")"
  [ -n "$LX_TMP" ] || LX_TMP="/tmp"
fi
mkdir -p "$LX_TMP" 2>/dev/null || true

LX_DOWNLOADS="${LIXINGER_DOWNLOADS:-$LX_HOME/Downloads}"
LX_CREDS="${LIXINGER_CREDS:-$LX_HOME/.config/lixinger-download/creds.json}"

case "$LX_OS" in
  mac)
    LX_BROWSER_DATA="$HOME/Library/Application Support"
    LX_CACHE="$HOME/Library/Caches"
    ;;
  windows)
    _lx_local="$(lx_slash "${LOCALAPPDATA:-$HOME/AppData/Local}")"
    LX_BROWSER_DATA="$_lx_local"
    LX_CACHE="$_lx_local"
    ;;
  *)
    LX_BROWSER_DATA="${XDG_CONFIG_HOME:-$HOME/.config}"
    LX_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
    ;;
esac

# 兼容 lib_pdf.sh / 日期分支历史变量
IS_MAC=0
[ "$LX_OS" = "mac" ] && IS_MAC=1

# Windows Git Bash 常只有 python.exe，没有 python3（官方安装器不放 python3.exe）。
# 全 skill 有 20+ 处 `python3 ...` 调用，逐处改易漏且侵入大 —— 这里在缺失时定义同名函数转发，
# 所有调用点无需改动。LX_PY 记录真实解释器，供诊断/打印。
LX_PY="python3"
if ! command -v python3 >/dev/null 2>&1; then
  if command -v python >/dev/null 2>&1; then
    LX_PY="python"
    python3() { python "$@"; }
  elif command -v py >/dev/null 2>&1; then
    LX_PY="py -3"
    python3() { py -3 "$@"; }
  fi
fi

# 绝对路径：POSIX 或 Windows 盘符（C:/... 与 C:\... 均可）
lx_is_abs_path() {
  case "$1" in
    /*) return 0 ;;
    [A-Za-z]:/* | [A-Za-z]:\\*) return 0 ;;
    *) return 1 ;;
  esac
}

# Git Bash 的 /c/Users/... 要转成 C:/Users/... 再传给 Windows 原生 Python。
# 非 Windows 平台原样返回。
lx_native_path() {
  local p="${1:-}"
  if [ "$LX_OS" = "windows" ]; then
    p="${p//\\//}"
    if [[ "$p" =~ ^/([A-Za-z])/(.*)$ ]]; then
      # 盘符统一大写（用 tr，不用 ${var^^} —— macOS 自带 bash 3.2 不支持）
      local d
      d="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
      p="${d}:/${BASH_REMATCH[2]}"
    fi
  fi
  printf '%s' "$p"
}

export LX_OS LX_VENV LX_CLI LX_PIP LX_TMP LX_HOME LX_DOWNLOADS LX_CREDS \
       LX_BROWSER_DATA LX_CACHE LX_PY IS_MAC

# 🔴 Windows 专项（2026-11-12 真机实测）：浏览器链路完全不可用时，主脚本仍会
#   ① 把 browser_start_session 的失败吞进 /dev/null 并打印「✅ 会话已开启」；
#   ② 继续跑完 CSV/PDF 全流程，空转数分钟，最后 0 文件落盘。
#   提供统一前置守卫：确认守护进程在跑、且浏览器确实连上，否则立即明确失败。
#   只在输出【明确出现】"Connected clients: 0" 时才判连接失败，
#   字段不存在的旧版 CLI / macOS 不受影响。LX_SKIP_DAEMON_CHECK=1 可跳过（离线调试用）。
lx_require_daemon() {
  local cli="${1:-$LX_CLI}" st
  [ "${LX_SKIP_DAEMON_CHECK:-0}" = "1" ] && return 0
  [ -x "$cli" ] || { echo "❌ 浏览器 CLI 不可用: ${cli}" >&2; return 1; }
  st="$("$cli" status 2>/dev/null)"
  if ! printf '%s' "$st" | grep -q "Daemon is running"; then
    echo "❌ 浏览器守护进程未运行 → 先执行: bash scripts/setup_env.sh --install" >&2
    echo "   （当前 CLI: ${cli}）" >&2
    return 1
  fi
  if printf '%s' "$st" | grep -qE "Connected clients: *0"; then
    echo "❌ 守护进程已起但浏览器未连接（Connected clients: 0）" >&2
    echo "   → WorkBuddy 设置→智能体→浏览器操控 开启开关并装好扩展，然后完全退出并重启浏览器" >&2
    return 1
  fi
  return 0
}
