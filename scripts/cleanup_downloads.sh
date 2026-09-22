#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 · ~/Downloads 孤儿临时文件清理工具
#
# 背景（2026-09-22 实测）：
#   主流程的 lib_orphans.sh 会把 ~/Downloads 里的「未确认*.crdownload」
#   孤儿 mv 到 ~/Library/Caches/.../orphans 暂存目录。但在 WorkBuddy 沙箱里，
#   对 ~/Downloads 的 mv/rm 会被拦截（属个人目录高风险操作），导致残留堆积，
#   只能事后手动清。
#
#   本脚本就是那个「事后一键清理」工具：专门扫 ~/Downloads，把浏览器程序化
#   下载留下的孤儿临时文件清掉。设计原则（沿用 lib_orphans 的安全边界）：
#     🔒 只认「未确认*.crdownload / Unconfirmed*.crdownload」这两种模式，
#        绝不碰老板自己的正常下载（如 报表.xlsx.crdownload）。
#     🔒 默认只列出（--dry-run），不删任何东西；要动必须显式加 --trash / --rm。
#     🔒 --trash 移到 macOS 回收站（~/.Trash），可随时从 Finder 还原；
#        --rm 才永久删，且必须再带 --yes 二次确认。
#
# 用法：
#   bash cleanup_downloads.sh                 # 仅列出，不删
#   bash cleanup_downloads.sh --trash        # 移入回收站（推荐，可还原）
#   bash cleanup_downloads.sh --rm --yes     # 永久删除（不可恢复）
#   LIXINGER_DOWNLOADS=/path/to/dir bash cleanup_downloads.sh --trash
# ============================================================

set -u

DOWNLOADS="${LIXINGER_DOWNLOADS:-$HOME/Downloads}"

# 只认这两种孤儿模式（与 lib_orphans.sh 完全一致，绝不扩大范围）
PAT_ZH='未确认*.crdownload'
PAT_EN='Unconfirmed*.crdownload'

DRY=1          # 默认 dry-run
MODE=""        # trash | rm
YES=0

usage() {
  cat <<'EOF'
清理 ~/Downloads 里的孤儿临时文件（浏览器程序化下载残留）。

用法:
  cleanup_downloads.sh [--dry-run]   列出孤儿，不删除（默认）
  cleanup_downloads.sh --trash      移入回收站 ~/.Trash（可还原，推荐）
  cleanup_downloads.sh --rm --yes   永久删除（不可恢复，需二次确认）

环境变量:
  LIXINGER_DOWNLOADS   下载目录（默认 $HOME/Downloads）

安全边界: 只匹配 未确认*.crdownload / Unconfirmed*.crdownload，
          不碰任何其它 .crdownload（如 报表.xlsx.crdownload）。
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY=1; MODE="" ;;
    --trash)      DRY=0; MODE=trash ;;
    --rm)         DRY=0; MODE=rm ;;
    --yes)        YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "❌ 未知参数: $arg"; echo; usage; exit 2 ;;
  esac
done

# ---- 收集孤儿（find -print0 + read -d ''，安全处理含空格文件名）----
ORPHANS=()
while IFS= read -r -d '' f; do
  ORPHANS+=("$f")
done < <(find "$DOWNLOADS" -maxdepth 1 \( -name "$PAT_ZH" -o -name "$PAT_EN" \) -print0 2>/dev/null)

n=${#ORPHANS[@]}
if [ "$n" -eq 0 ]; then
  echo "✅ $DOWNLOADS 没有孤儿临时文件（未确认*/Unconfirmed*.crdownload）"
  exit 0
fi

echo "在 $DOWNLOADS 发现 ${n} 个孤儿临时文件："
for f in "${ORPHANS[@]}"; do
  sz=$(stat -f%z "$f" 2>/dev/null || echo '?')
  printf '  • %s  (%sB)\n' "$(basename "$f")" "$sz"
done

# ---- dry-run：只列不删 ----
if [ "$DRY" -eq 1 ]; then
  echo
  echo "（以上为预览，未做任何修改。加 --trash 移入回收站 / --rm --yes 永久删除）"
  exit 0
fi

# ---- 移入回收站（trash 目录用兜底，避免 HOME 未导出时 set -u 触发 unbound）----
if [ "$MODE" = "trash" ]; then
  trash_dir="${HOME:-/Users/$(id -un)}/.Trash"
  mkdir -p "$trash_dir" 2>/dev/null
  moved=0; fail=0
  for f in "${ORPHANS[@]}"; do
    if mv -f "$f" "$trash_dir/" 2>/dev/null; then
      moved=$((moved+1))
    else
      fail=$((fail+1))
    fi
  done
  echo
  if [ "$moved" -gt 0 ]; then
    echo "✅ 已移入回收站 ${moved} 个 → ${trash_dir}（可随时从 Finder 回收站还原）"
  fi
  if [ "$fail" -gt 0 ]; then
    echo "⚠️ ${fail} 个移动失败（可能因 WorkBuddy 沙箱拦截 ~/Downloads 写入）。"
    echo "   请在 Terminal.app 中直接运行本脚本：bash \"$(cd "$(dirname "$0")" && pwd)/$(basename "$0")\" --trash"
  fi
  exit 0
fi

# ---- 永久删除（需 --yes）----
if [ "$MODE" = "rm" ]; then
  if [ "$YES" -ne 1 ]; then
    echo
    echo "⚠️ 永久删除不可恢复。确认请加 --yes："
    echo "   bash cleanup_downloads.sh --rm --yes"
    exit 1
  fi
  done_n=0; fail=0
  for f in "${ORPHANS[@]}"; do
    if rm -f "$f" 2>/dev/null; then
      done_n=$((done_n+1))
    else
      fail=$((fail+1))
    fi
  done
  echo
  if [ "$done_n" -gt 0 ]; then
    echo "🗑️  已永久删除 ${done_n} 个"
  fi
  if [ "$fail" -gt 0 ]; then
    echo "⚠️ ${fail} 个删除失败（可能因 WorkBuddy 沙箱拦截）。请在 Terminal.app 中运行。"
  fi
  exit 0
fi
