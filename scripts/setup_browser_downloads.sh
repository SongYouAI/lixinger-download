#!/usr/bin/env bash
# 让 Chrome / Edge 的下载行为与 QQ 浏览器一致（静默下载，不弹「存储为」对话框）
#
# 为什么需要：WorkBuddy 浏览器扩展只能点击页面元素，点不掉 macOS 原生「存储为」对话框。
#   Chrome 默认 download.prompt_for_download=true → 每次下载都卡在原生对话框，文件永不落盘。
#   另外 always_open_pdf_externally 未开时，点年报 PDF 只会「在线预览」不下载。
#
# 改两项（每个 Profile）：
#   plugins.always_open_pdf_externally = true   # PDF 直接下载，不在浏览器里预览
#   download.prompt_for_download       = false  # 不再每次询问保存位置
#
# 用法:
#   bash setup_browser_downloads.sh            # 改 Chrome + Edge（会先请你退出浏览器）
#   bash setup_browser_downloads.sh --only chrome
#   bash setup_browser_downloads.sh --revert   # 从最近备份还原
#   bash setup_browser_downloads.sh --check    # 只读，不改
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_platform.sh"

ONLY=""
MODE="apply"
while [ $# -gt 0 ]; do
  case "$1" in
    --only)   ONLY="$2"; shift 2 ;;
    --revert) MODE="revert"; shift ;;
    --check)  MODE="check"; shift ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

APPS=()
case "$ONLY" in
  "")      APPS=("Google Chrome" "Microsoft Edge") ;;
  chrome)  APPS=("Google Chrome") ;;
  edge)    APPS=("Microsoft Edge") ;;
  *) echo "--only 只支持 chrome / edge"; exit 2 ;;
esac

# 配置目录层级按平台不同：Windows 多一层 User Data
pref_dir() {  # $1=应用名
  case "$LX_OS" in
    mac)
      case "$1" in
        "Google Chrome") echo "$LX_BROWSER_DATA/Google/Chrome" ;;
        "Microsoft Edge") echo "$LX_BROWSER_DATA/Microsoft Edge" ;;
        *) echo "" ;;
      esac ;;
    windows)
      case "$1" in
        "Google Chrome") echo "$LX_BROWSER_DATA/Google/Chrome/User Data" ;;
        "Microsoft Edge") echo "$LX_BROWSER_DATA/Microsoft/Edge/User Data" ;;
        *) echo "" ;;
      esac ;;
    linux)
      case "$1" in
        "Google Chrome") echo "$LX_BROWSER_DATA/google-chrome" ;;
        "Microsoft Edge") echo "$LX_BROWSER_DATA/microsoft-edge" ;;
        *) echo "" ;;
      esac ;;
    *) echo "" ;;
  esac
}

BASE_HINT="$LX_BROWSER_DATA"
BAKDIR="$LX_HOME/.config/lixinger-download/prefs-backup"
mkdir -p "$BAKDIR"; chmod 700 "$BAKDIR"

app_proc() {  # Windows 进程名
  case "$1" in
    "Google Chrome") echo "chrome.exe" ;;
    "Microsoft Edge") echo "msedge.exe" ;;
    *) echo "" ;;
  esac
}

app_running() {  # $1=应用名
  if [ "$LX_OS" = "windows" ]; then
    local p; p="$(app_proc "$1")"
    [ -n "$p" ] && tasklist //FI "IMAGENAME eq $p" 2>/dev/null | grep -qi "$p"
  else
    osascript -e "application \"$1\" is running" 2>/dev/null | grep -qi true
  fi
}

quit_app() {
  echo "  → 正在退出 $1 …"
  if [ "$LX_OS" = "windows" ]; then
    # Windows 没有 SIGTERM 等价物；taskkill /F 是唯一可靠方式。
    # Git Bash 会把 /IM 当路径转换，必须写成 //IM。
    local p; p="$(app_proc "$1")"
    taskkill //IM "$p" //T //F >/dev/null 2>&1
    for _ in $(seq 1 15); do
      app_running "$1" || { echo "  ✅ 已退出 $1"; return 0; }
      sleep 1
    done
    echo "  ❌ $1 仍在运行，请手动退出后重跑"; return 1
  fi
  osascript -e "tell application \"$1\" to quit" >/dev/null 2>&1
  for _ in $(seq 1 8); do
    app_running "$1" || { echo "  ✅ 已退出 $1"; return 0; }
    sleep 1
  done
  # osascript 的 quit 常因「自动化」权限被静默拦掉 → 退回 SIGTERM。
  # Chrome/Edge 收到 TERM 会走正常关闭流程（会回写 Preferences），不会损坏配置。
  echo "  → osascript 退出无效，改用 SIGTERM …"
  killall -TERM "$1" >/dev/null 2>&1
  for _ in $(seq 1 15); do
    app_running "$1" || { echo "  ✅ 已退出 $1（SIGTERM）"; return 0; }
    sleep 1
  done
  echo "  ❌ $1 仍在运行，请手动退出（Cmd+Q）后重跑"; return 1
}

# 对单个 Preferences 文件做读/改/还原
patch_pref() {  # $1=prefs路径 $2=动作(apply|revert|check)
  local f="$1" act="$2"
  python3 - "$(lx_native_path "$f")" "$act" "$(lx_native_path "$BAKDIR")" <<'PY'
import json, os, re, shutil, sys, time

f, act, bakdir = sys.argv[1], sys.argv[2], sys.argv[3]
if not os.path.isfile(f):
    print("    ⏭️  无 Preferences（该浏览器可能从未启动）"); sys.exit(0)

# Windows 路径含盘符冒号，不能当文件名；只保留安全字符
bak = os.path.join(bakdir, re.sub(r"[^A-Za-z0-9._-]", "_", f) + ".bak")
with open(f, encoding="utf-8") as fh:
    d = json.load(fh)

plugins = d.setdefault("plugins", {})
download = d.setdefault("download", {})
cur_pdf = plugins.get("always_open_pdf_externally")
cur_prompt = download.get("prompt_for_download")

if act == "check":
    print(f"    always_open_pdf_externally = {cur_pdf}")
    print(f"    prompt_for_download        = {cur_prompt}")
    ok = (cur_pdf is True) and (cur_prompt is False)
    print("    " + ("✅ 已就绪" if ok else "⚠️ 未就绪"))
    sys.exit(0)

if act == "revert":
    if not os.path.isfile(bak):
        print("    ❌ 没找到备份，无法还原"); sys.exit(1)
    shutil.copy2(bak, f)
    print(f"    ✅ 已从备份还原: {os.path.basename(bak)}")
    sys.exit(0)

# apply: 先备份（只在第一次备份，保留最原始的）
if not os.path.isfile(bak):
    shutil.copy2(f, bak)
    print(f"    💾 已备份原始 Preferences → {os.path.basename(bak)}")

if cur_pdf is True and cur_prompt is False:
    print("    ⏭️  两项已是目标值，无需修改"); sys.exit(0)

plugins["always_open_pdf_externally"] = True
download["prompt_for_download"] = False

# 原子写：先写临时文件再替换，避免写一半把浏览器配置搞坏
tmp = f + ".tmp-lixinger"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(d, fh, separators=(",", ":"))
os.replace(tmp, f)
print(f"    ✅ 已改: always_open_pdf_externally={cur_pdf}→True, prompt_for_download={cur_prompt}→False")
PY
}

for APP in "${APPS[@]}"; do
  DIR=$(pref_dir "$APP")
  echo "=== $APP ==="
  if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then echo "  ⏭️  未安装（无配置目录）"; continue; fi

  if [ "$MODE" != "check" ]; then
    if app_running "$APP"; then
      quit_app "$APP" || continue
    fi
  fi

  # 处理所有 Profile（Default + Profile N）
  for PREF in "$DIR"/Default/Preferences "$DIR"/Profile*/Preferences; do
    [ -f "$PREF" ] || continue
    echo "  ── Profile: $(basename "$(dirname "$PREF")")"
    patch_pref "$PREF" "$MODE"
  done
done

echo
case "$MODE" in
  check)  echo "只读检查完毕。要改就运行: bash $0" ;;
  revert) echo "还原完成。请重新打开浏览器。" ;;
  *)      echo "改完了。请重新打开 Chrome / Edge 再测试下载。"
          echo "还原: bash $0 --revert" ;;
esac
