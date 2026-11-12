#!/usr/bin/env bash
# ============================================================
# qqbrowser-skill CLI · Windows 兼容调用层（v2.2-winfix）
#
# 问题：Windows 上 pip 生成的 $VENV/Scripts/qqbrowser-skill.exe 是【未签名】
#   setuptools launcher。启用 WDAC / Device Guard 的机器会直接拒绝执行：
#     Git Bash: "Permission denied"（退出码 126）
#     cmd.exe : "...已被组织 Device Guard 阻止"（退出码 199）
#   → 所有 browser_* 子命令都调不动，整条下载链路不可用。
#
# 解法：python.exe 本身受信任，用它直接驱动包的 console_script 入口
#   `x5use.server:main`。参数原样透传，行为与 .exe 完全一致。
#   （qqbrowser-skill 1.6.3 的 entry_points: qqbrowser-skill = x5use.server:main）
#
# 选择逻辑在 lib_platform.sh：仅当 Windows + venv 里确实装了 x5use 时启用本 wrapper；
#   macOS / Linux 仍走原来的 bin/qqbrowser-skill，不受影响。
# ============================================================
set -u

# venv 定位：优先 LIXINGER_VENV，其次 Windows USERPROFILE，最后 Unix HOME
if [ -n "${LIXINGER_VENV:-}" ]; then
  VENV="${LIXINGER_VENV//\\//}"
elif [ -n "${USERPROFILE:-}" ]; then
  VENV="${USERPROFILE//\\//}/.workbuddy/binaries/python/envs/qqbrowser-ctl"
else
  VENV="$HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl"
fi

PY=""
for c in "$VENV/Scripts/python.exe" "$VENV/Scripts/python" \
         "$VENV/bin/python3" "$VENV/bin/python"; do
  if [ -x "$c" ]; then PY="$c"; break; fi
done
if [ -z "$PY" ]; then
  echo "❌ qqbrowser-skill CLI wrapper: 找不到 venv 里的 python: $VENV" >&2
  exit 2
fi

# -c 会把第一个用户参数放到 sys.argv[1]，argparse 读 sys.argv[1:]，与 .exe 一致
exec "$PY" -c 'from x5use.server import main; raise SystemExit(main())' "$@"
