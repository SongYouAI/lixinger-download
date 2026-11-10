#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 · 跨平台静态自检（不需要浏览器、不联网）
#
# 用法: bash scripts/selftest.sh
# 退出码: 0=全部必需项通过, 1=有 FAIL
#
# 用途：在 Windows（Git Bash / MSYS2 / WSL）上装完后先跑这个，
#       确认平台抽象层、路径转换、编码都正常，再做端到端下载验收。
#       PowerShell 不能执行 .sh，不在支持范围。
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib_platform.sh"

PASS=0; FAIL=0; WARN=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "=========================================="
echo " 理杏仁下载 · 跨平台静态自检"
echo " 平台: $LX_OS   终端: $(uname -s 2>/dev/null || echo '?')"
echo " 脚本目录: $SCRIPT_DIR"
echo "=========================================="

# ---- 1. 平台识别 ----
echo "[1/9] 平台识别"
case "$LX_OS" in
  mac|linux|windows) ok "LX_OS=$LX_OS" ;;
  *) bad "无法识别平台（uname=$(uname -s 2>/dev/null)）" ;;
esac
if [ "$LX_OS" = "windows" ]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ok "Git Bash / MSYS2 终端" ;;
    Linux*) warn "当前是 WSL：Windows 侧浏览器扩展与 WSL 跨边界通信未验证，端到端可能不通" ;;
    *) warn "未知 Windows 终端" ;;
  esac
fi

# ---- 2. 导出变量 ----
echo "[2/9] 平台抽象层导出变量"
for v in LX_VENV LX_CLI LX_PIP LX_TMP LX_HOME LX_DOWNLOADS LX_CREDS LX_BROWSER_DATA LX_CACHE; do
  if [ -n "${!v:-}" ]; then ok "$v = ${!v}"; else bad "$v 为空"; fi
done

# ---- 3. 全部 shell 语法 ----
echo "[3/9] shell 语法 (bash -n)"
SYNTAX_FAIL=0
for f in "$SCRIPT_DIR"/*.sh; do
  bash -n "$f" 2>/dev/null || { bad "语法错误: $(basename "$f")"; SYNTAX_FAIL=1; }
done
[ "$SYNTAX_FAIL" -eq 0 ] && ok "全部 $(ls -1 "$SCRIPT_DIR"/*.sh | wc -l | tr -d ' ') 个 .sh 通过"

# ---- 4. Python 可用性 ----
echo "[4/9] Python"
if command -v python3 >/dev/null 2>&1; then
  PV=$(python3 --version 2>&1 | awk '{print $2}')
  MAJOR=$(echo "$PV" | cut -d. -f1); MINOR=$(echo "$PV" | cut -d. -f2)
  if [ "${MAJOR:-0}" -ge 3 ] && [ "${MINOR:-0}" -ge 9 ]; then ok "Python ${PV}（命令: ${LX_PY}）"
  else bad "python3 $PV 版本过低（需 ≥3.9）"; fi
  PY_OK=1
else
  bad "未找到 python3"; PY_OK=0
fi
if [ "$PY_OK" -eq 1 ]; then
  if python3 - "$SCRIPT_DIR" <<'PY'
import ast, glob, sys
for f in glob.glob(sys.argv[1] + "/*.py"):
    ast.parse(open(f, encoding="utf-8").read(), filename=f)
sys.exit(0)
PY
  then ok "全部 .py 语法通过"; else bad ".py 语法错误"; fi
fi

# ---- 5. 临时目录：shell 写 / Python 读 同一物理路径（Windows 关键项）----
echo "[5/9] 临时目录路径一致性"
PROBE="$LX_TMP/.lx_selftest_probe.txt"
printf 'path-ok\n' > "$PROBE" 2>/dev/null
if [ ! -f "$PROBE" ]; then
  bad "shell 无法写 LX_TMP: $PROBE"
elif [ "$PY_OK" -eq 1 ]; then
  R=$(python3 - "$PROBE" <<'PY'
import sys
print(open(sys.argv[1], encoding="utf-8").read().strip())
PY
  )
  [ "$R" = "path-ok" ] && ok "shell 写 → Python 读 一致 ($LX_TMP)" \
    || bad "Python 读不到 shell 写的文件（Windows 路径转换失败）: 读到 [$R]"
fi
rm -f "$PROBE" 2>/dev/null
if TMPL=$(mktemp "$LX_TMP/.lx_selftest_mk.XXXXXX" 2>/dev/null) && [ -f "$TMPL" ]; then
  ok "mktemp 模板可用（lib_orphans.sh 依赖）"; rm -f "$TMPL" 2>/dev/null
else
  bad "mktemp 模板不可用: $LX_TMP/.lx_selftest_mk.XXXXXX"
fi

# ---- 6. 中文编码往返 ----
echo "[6/9] UTF-8 中文编码"
ENC="$LX_TMP/.lx_selftest_enc.txt"
printf '理杏仁年报中文校验\n' > "$ENC" 2>/dev/null
if [ "$PY_OK" -eq 1 ] && [ -f "$ENC" ]; then
  R=$(python3 - "$ENC" <<'PY'
import sys
print(open(sys.argv[1], encoding="utf-8").read().strip())
PY
  )
  [ "$R" = "理杏仁年报中文校验" ] && ok "中文读写一致" || bad "中文编码不一致: 读到 [$R]"
  if printf '2024年年度报告\n' > "$ENC" && grep -q '年度报告' "$ENC" 2>/dev/null; then
    ok "grep 中文正则可用（翻页/年报匹配依赖）"
  else
    bad "grep 中文正则不可用 → 检查终端 locale 是否为 UTF-8"
  fi
fi
rm -f "$ENC" 2>/dev/null

# ---- 7. 路径判定与转换 ----
echo "[7/9] 路径判定与转换"
if lx_is_abs_path "/tmp/x" && lx_is_abs_path "C:/Users/x" && lx_is_abs_path 'C:\Users\x' \
   && ! lx_is_abs_path "relative/x"; then
  ok "绝对路径判定（POSIX + Windows 盘符）"
else
  bad "绝对路径判定异常"
fi
if [ "$LX_OS" = "windows" ]; then
  N=$(lx_native_path "/c/Users/someone/Downloads")
  case "$N" in
    [A-Za-z]:/*) ok "MSYS → 原生路径: $N" ;;
    *) bad "lx_native_path 转换失败: [$N]" ;;
  esac
else
  N=$(lx_native_path "/tmp/plain")
  [ "$N" = "/tmp/plain" ] && ok "非 Windows 路径原样返回" || bad "lx_native_path 误改路径: [$N]"
fi

# ---- 8. 残留平台耦合（代码行）----
echo "[8/9] 残留平台耦合"
LEAK=$(grep -nE '/tmp/|/Users/niusl321|Library/Application Support|Library/Caches' "$SCRIPT_DIR"/*.sh \
       2>/dev/null | grep -v 'lib_platform.sh' | grep -v 'selftest.sh' \
       | grep -vE ':[0-9]+:[[:space:]]*#' || true)
if [ -z "$LEAK" ]; then ok "无硬编码 /tmp、个人路径、macOS 专用目录（代码行）"
else bad "仍有硬编码平台路径:"; printf '%s\n' "$LEAK" | sed 's/^/       /'; fi

# macOS bash 3.2 在 set -u 下会把「变量紧跟中文」误判成变量名的一部分，报 unbound variable。
# SKILL.md 有专条；这里扫全部 .sh 代码行防复发。
CJK=$(python3 - "$SCRIPT_DIR" 2>/dev/null <<'PY'
import glob, re, sys
out = []
for f in sorted(glob.glob(sys.argv[1] + "/*.sh")):
    for i, l in enumerate(open(f, encoding="utf-8"), 1):
        if l.lstrip().startswith("#"):
            continue
        if re.search(r"\$[A-Za-z_][A-Za-z_0-9]*[^\x00-\x7f]", l):
            out.append(f + ":" + str(i))
print("\n".join(out))
PY
)
if [ -z "$CJK" ]; then ok "无变量边界陷阱（bash 3.2 变量紧跟中文）"
else bad "存在变量边界陷阱:"; printf '%s\n' "$CJK" | sed 's/^/       /'; fi

# ---- 9. 环境依赖（不判失败，只提示）----
echo "[9/9] 环境依赖（提示项）"
[ -x "$LX_CLI" ] && ok "CLI 就位: $LX_CLI" || warn "CLI 未安装: ${LX_CLI}（跑 bash scripts/setup_env.sh --install）"
[ -f "$LX_CREDS" ] && ok "凭证存在: $LX_CREDS" || warn "缺凭证: ${LX_CREDS}（见 references/01-environment-setup.md 步骤 5）"
if [ -f "$ROOT/.gitattributes" ]; then
  if git -C "$ROOT" check-attr eol -- scripts/download_company.sh 2>/dev/null | grep -q 'eol: lf'; then
    ok ".gitattributes 生效（.sh 强制 LF）"
  else
    warn ".gitattributes 存在但当前不是 git 仓库，无法验证（拷贝目录部署时正常）"
  fi
else
  bad "缺 .gitattributes（Windows CRLF 会让 bash 报 \$'\\r': command not found）"
fi
if [ "$LX_OS" = "windows" ]; then
  for d in "$LX_BROWSER_DATA/Google/Chrome/User Data" "$LX_BROWSER_DATA/Microsoft/Edge/User Data"; do
    [ -d "$d" ] && ok "浏览器配置目录: $d" || warn "未找到（浏览器可能没装/没启动过）: $d"
  done
fi

echo "=========================================="
echo " 结果: ✅ $PASS 通过 / ❌ $FAIL 失败 / ⚠️  $WARN 提示"
if [ "$FAIL" -eq 0 ]; then
  echo " 静态自检只覆盖静态项；下载链路能不能跑，请实际下载一家公司确认："
  echo "   bash scripts/download_company.sh --name 贵州茅台 --market sh --code 600519 --dest <绝对路径> --years 10"
  echo "   然后跑 verify_csv_units.py 与 audit_annual_pdfs.py，并用 Python 盘真实落盘。"
else
  echo " 请修复上面的 ❌ 项后重跑。"
fi
echo "=========================================="
exit "$FAIL"
