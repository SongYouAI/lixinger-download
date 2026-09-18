#!/usr/bin/env bash
# ============================================================
# 理杏仁 - 批量串行下载（多公司）
#
# 用法:
#   bash batch_download.sh --list companies.txt --dest "/Volumes/KIOXIA/理杏仁下载" [--years 10]
#
# 清单文件格式（每行一条，# 开头为注释，空行跳过）:
#   公司名|market|code
#   华能国际|sh|600011
#   华润电力|hk|00836
#
# 产出:
#   {dest}/{公司名}/   （目录结构见 SKILL.md 输出目录规范）
#   日志: /tmp/lx_batch_<时间戳>.log
# ============================================================
set -uo pipefail

LIST=""; DEST=""; YEARS=10
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINGLE="$SCRIPT_DIR/download_company.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)  LIST="$2";  shift 2;;
    --dest)  DEST="$2";  shift 2;;
    --years) YEARS="$2"; shift 2;;
    -h|--help) sed -n '3,16p' "$0" | sed 's/^# *//'; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

if [ -z "$LIST" ] || [ -z "$DEST" ]; then
  echo "❌ 缺少参数。用法: $0 --list companies.txt --dest <目标目录> [--years 10]"
  exit 1
fi
if [ ! -f "$LIST" ]; then echo "❌ 清单文件不存在: $LIST"; exit 1; fi
if [ ! -x "$SINGLE" ]; then echo "❌ 未找到主脚本: $SINGLE"; exit 1; fi

LOG="/tmp/lx_batch_$(date +%m%d_%H%M%S).log"
: > "$LOG"
echo "=========================================="
echo " 理杏仁批量下载"
echo " 清单: $LIST   目标: $DEST   年数: $YEARS"
echo " 日志: $LOG"
echo "=========================================="

TOTAL=$(grep -vE '^\s*(#|$)' "$LIST" | wc -l | tr -d ' ')
N=0
while IFS= read -r line; do
  # 跳过注释与空行
  case "$line" in ''|\#*) continue;; esac
  N=$((N+1))
  NAME=$(echo "$line" | cut -d'|' -f1 | xargs)   # xargs 去首尾空格
  MKT=$(echo "$line"  | cut -d'|' -f2 | xargs)
  CODE=$(echo "$line" | cut -d'|' -f3 | xargs)
  if [ -z "$NAME" ] || [ -z "$MKT" ] || [ -z "$CODE" ]; then
    echo "  ⚠️  清单第 $N 行格式不对，跳过: $line"; continue
  fi
  echo "───── [$N/$TOTAL] $NAME ($MKT$CODE) $(date '+%H:%M:%S') ─────"
  echo "########## [$N/$TOTAL] 开始: $NAME ($MKT$CODE) $(date '+%H:%M:%S') ##########" >> "$LOG"
  bash "$SINGLE" --name "$NAME" --market "$MKT" --code "$CODE" --dest "$DEST" --years "$YEARS" >> "$LOG" 2>&1
  EC=$?
  echo "########## [$N/$TOTAL] 结束: $NAME 退出码=$EC $(date '+%H:%M:%S') ##########" >> "$LOG"
  # 即时播报该家的失败项（不要等全跑完才发现）
  tail -40 "$LOG" | grep -E "❌失败项|⚠️.*未检测到|⏭️理杏仁未收录|PDF: |CSV: " | tail -6
done < "$LIST"

echo "=========================================="
echo " 批量结束，共 $N 家。日志: $LOG"
echo " ⚠️ 退出码 0 ≠ 成功，请用 Python 盘真实落盘（见 references/04 第三节）"
echo "=========================================="
