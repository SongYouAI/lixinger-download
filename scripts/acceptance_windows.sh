#!/usr/bin/env bash
# ============================================================
# 可选工具：一次性串跑自检 + 端到端下载 + 两道验收 + 落盘盘点
#
# ⚠️ 平台状态：本 skill 只在 macOS 上实测过；本脚本也只在 macOS 上验证过逻辑，
#    Windows 上从未运行。它只是把步骤串起来省事，不是必需流程，也不是可用性依据。
#
# 用法：
#   bash scripts/acceptance_windows.sh --dest "C:/Users/<你>/Desktop/理杏仁验收"
#   bash scripts/acceptance_windows.sh --dest "D:/lx" --name 长江电力 --market sh --code 600900 --years 10
#
# 前提（本脚本不代做）：
#   1. Python ≥3.9 已装且加入 PATH
#   2. Git for Windows 已装，命令在 Git Bash 里执行（PowerShell 不能跑 .sh）
#   3. QQ 浏览器已装并打开过一次；qqbrowser-skill 已装、守护进程已起
#   4. ~/.config/lixinger-download/creds.json 已写入
#
# 退出码：0=全部 PASS；非 0=有 FAIL。完整日志在 $LX_TMP/lx_acceptance_<时间戳>.log
# 本脚本不 push、不改浏览器 Preferences、不删文件。
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_platform.sh"

DEST=""; NAME="贵州茅台"; MARKET="sh"; CODE="600519"; YEARS="10"
while [ $# -gt 0 ]; do
  case "$1" in
    --dest)   DEST="${2:-}"; shift 2 ;;
    --name)   NAME="${2:-}"; shift 2 ;;
    --market) MARKET="${2:-}"; shift 2 ;;
    --code)   CODE="${2:-}"; shift 2 ;;
    --years)  YEARS="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "❌ 未知参数: $1"; exit 2 ;;
  esac
done

if [ -z "$DEST" ]; then
  echo "❌ 必填 --dest（绝对路径，例如 C:/Users/<你>/Desktop/理杏仁验收）"; exit 2
fi
if ! lx_is_abs_path "$DEST"; then
  echo "❌ --dest 必须是绝对路径（当前: ${DEST}）"; exit 2
fi
if [ "$LX_OS" != "windows" ]; then
  echo "⚠️ 当前平台 ${LX_OS}，不是 Windows。本脚本用于 Windows 真机验收；Mac 上跑只会验证 Mac。"
fi

LOG="$LX_TMP/lx_acceptance_$(date +%Y%m%d_%H%M%S).log"
STEP_OUT="$LX_TMP/.lx_accept_step.txt"
PASS=0; FAIL=0

# 🔴 Windows 专项：audit_annual_pdfs.py 依赖 pymupdf，venv 与全局 python3 是隔离的。
#   原版写死全局 python3 → Windows 上即使 venv 装了 pymupdf，[6/7] 仍报
#   "❌ 需要 pymupdf" 并 exit 2。改为优先挑【确实能 import pymupdf】的解释器。
LX_AUDIT_PY="python3"
for _c in "$LX_VENV/Scripts/python.exe" "$LX_VENV/Scripts/python" \
          "$LX_VENV/bin/python3" "$LX_VENV/bin/python" python3; do
  if { [ -x "$_c" ] || command -v "$_c" >/dev/null 2>&1; } \
     && "$_c" -c 'import pymupdf' >/dev/null 2>&1; then
    LX_AUDIT_PY="$_c"; break
  fi
done

echo "=========================================="
echo " Windows 真机验收 · $NAME ($MARKET$CODE)"
echo " 平台: $LX_OS    Python: $LX_PY"
echo " 验收解释器: $LX_AUDIT_PY"
echo " 输出目录: $DEST"
echo " 日志: $LOG"
echo "=========================================="
: > "$LOG"

step() {  # $1=标签 ; 其余=命令
  local label="$1"; shift
  echo "── $label"
  "$@" > "$STEP_OUT" 2>&1
  local rc=$?
  cat "$STEP_OUT" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    echo "   ✅ PASS"; PASS=$((PASS+1))
  else
    echo "   ❌ FAIL (退出码 $rc)"; FAIL=$((FAIL+1))
    tail -12 "$STEP_OUT" | sed 's/^/     /'
  fi
}

# ---- 1. 静态自检 ----
step "[1/7] 跨平台静态自检" bash "$SCRIPT_DIR/selftest.sh"

# ---- 2. 环境自检（退出码 = 缺失项数）----
step "[2/7] 环境自检（守护进程 / 浏览器连接）" bash "$SCRIPT_DIR/setup_env.sh"

# ---- 3. 自动登录：跑完整模式（已登录秒退 / 未登录自动填表），验证「无需人工登录」----
# 不用 --check：它只查当下状态，登录态过期时会误报 FAIL，而下载脚本本来就会自动登录。
echo "── [3/7] 理杏仁自动登录"
bash "$SCRIPT_DIR/lixinger_login.sh" > "$STEP_OUT" 2>&1
RC=$?; cat "$STEP_OUT" >> "$LOG"
if [ "$RC" -eq 0 ] && grep -qE "已是登录态|登录成功" "$STEP_OUT"; then
  echo "   ✅ PASS"; PASS=$((PASS+1))
else
  echo "   ❌ FAIL (退出码 ${RC}，或未出现自动登录成功)"; FAIL=$((FAIL+1))
  tail -12 "$STEP_OUT" | sed 's/^/     /'
fi

# ---- 4. 端到端下载 ----
step "[4/7] 端到端下载 $NAME 近 $YEARS 年（PDF + CSV）" \
  bash "$SCRIPT_DIR/download_company.sh" \
    --name "$NAME" --market "$MARKET" --code "$CODE" \
    --dest "$DEST" --years "$YEARS"

# ---- 5. CSV 单位量级核验 ----
step "[5/7] CSV 单位核验" \
  "$LX_AUDIT_PY" "$(lx_native_path "$SCRIPT_DIR/verify_csv_units.py")" \
    "$(lx_native_path "$DEST/$NAME/理杏仁财报/")"

# ---- 6. 年报名副其实性审计 ----
step "[6/7] 年报审计" \
  "$LX_AUDIT_PY" "$(lx_native_path "$SCRIPT_DIR/audit_annual_pdfs.py")" "$(lx_native_path "$DEST")"

# ---- 7. Python 盘真实落盘 ----
echo "── [7/7] 真实落盘盘点"
"$LX_AUDIT_PY" - "$(lx_native_path "$DEST")" "$NAME" "$YEARS" <<'PY' > "$STEP_OUT" 2>&1
import os, sys
root, name, years = sys.argv[1], sys.argv[2], int(sys.argv[3])
base = os.path.join(root, name)
pdfd, csvd = os.path.join(base, "年报PDF"), os.path.join(base, "理杏仁财报")
pdfs = [f for f in os.listdir(pdfd) if f.lower().endswith(".pdf") and not f.startswith("._")] if os.path.isdir(pdfd) else []
csvs = [f for f in os.listdir(csvd) if f.lower().endswith(".csv") and not f.startswith("._")] if os.path.isdir(csvd) else []
small = [f for f in pdfs if os.path.getsize(os.path.join(pdfd, f)) < 100 * 1024]
dots, stray = [], []
for dp, _, fs in os.walk(base):
    for f in fs:
        if f.startswith("._"): dots.append(os.path.join(dp, f))
        # 只判 skill 自己产出的年报 PDF；用户原有的研报等同级文件不算散落
        if dp == base and "年度报告" in f and f.lower().endswith(".pdf"): stray.append(f)
bad = []
if len(pdfs) < years: bad.append(f"年报PDF {len(pdfs)} 份 < 期望 {years}")
if len(csvs) != 7: bad.append(f"CSV {len(csvs)} 张 ≠ 期望 7")
if small: bad.append(f"空壳 PDF(<100KB): {small}")
if dots: bad.append(f"._ 垃圾 {len(dots)} 个")
if stray: bad.append(f"根目录散落: {stray}")
print(f"  PDF {len(pdfs)} 份 / CSV {len(csvs)} 张 / 空壳 {len(small)} / ._ 垃圾 {len(dots)} / 散落 {len(stray)}")
for b in bad: print("  ❌ " + b)
sys.exit(1 if bad else 0)
PY
RC=$?; cat "$STEP_OUT" >> "$LOG"
if [ "$RC" -eq 0 ]; then
  echo "   ✅ PASS"; PASS=$((PASS+1))
else
  echo "   ❌ FAIL"; FAIL=$((FAIL+1)); tail -12 "$STEP_OUT" | sed 's/^/     /'
fi

echo "=========================================="
echo " 结果: ✅ $PASS 通过 / ❌ $FAIL 失败"
echo " 完整日志: $LOG"
if [ "$FAIL" -eq 0 ]; then
  echo " ✅ 本机（${LX_OS}）全部项通过，说明这台机器跑通了。"
  echo "    注意：本 skill 原本只在 macOS 实测过；首次在新平台跑通请自行复核产物。"
else
  echo " ⛔ 有项未通过，请按完整日志排查，不要当作已可用。"
fi
echo "=========================================="
exit "$FAIL"
