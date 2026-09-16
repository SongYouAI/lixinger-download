#!/usr/bin/env bash
# ============================================================
# 理杏仁 - 单公司财报完整下载
#
# 用法:
#   bash download_company.sh --name 长江电力 --market sh --code 600900 \
#        --dest "/Volumes/KIOXIA/理杏仁下载" [--years 10] [--skip-pdf] [--skip-csv]
#
# 产出:
#   {dest}/{name}/
#     ├── 年报PDF/{name}_{YYYY}年年度报告.pdf   (10年)
#     └── {name}_{报表}_*.csv                   (7类, 10年)
# ============================================================
set -uo pipefail

# ---------- 默认参数 ----------
NAME=""; MARKET=""; CODE=""; DEST=""; YEARS=10
SKIP_PDF=0; SKIP_CSV=0
SID="lixinger-dl-$(date +%s)"

# ---------- 路径 ----------
VENV="${LIXINGER_VENV:-$HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl}"
CLI="$VENV/bin/qqbrowser-skill"
BASE="https://www.lixinger.com/analytics/company/detail"
DOWNLOADS="${LIXINGER_DOWNLOADS:-$HOME/Downloads}"

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --market) MARKET="$2"; shift 2;;
    --code) CODE="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --years) YEARS="$2"; shift 2;;
    --skip-pdf) SKIP_PDF=1; shift;;
    --skip-csv) SKIP_CSV=1; shift;;
    -h|--help) sed -n '3,13p' "$0" | sed 's/^# *//'; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

# ---------- 校验 ----------
if [ -z "$NAME" ] || [ -z "$MARKET" ] || [ -z "$CODE" ] || [ -z "$DEST" ]; then
  echo "❌ 缺少必填参数。用法: $0 --name 公司名 --market sh --code 600900 --dest 目标目录"
  exit 1
fi
if [ ! -x "$CLI" ]; then
  echo "❌ 未找到 CLI: $CLI → 先运行 scripts/setup_env.sh --install"
  exit 1
fi

# ---------- 日期范围（跨平台）----------
if [ "$(uname -s)" = "Darwin" ]; then
  START_DATE=$(date -v-${YEARS}y +%Y-%m-%d)
else
  START_DATE=$(date -d "${YEARS} years ago" +%Y-%m-%d)
fi
END_DATE=$(date +%Y-%m-%d)
QUERY="fs-owner-type=consolidated&start-date=${START_DATE}&end-date=${END_DATE}"
PREFIX="${BASE}/${MARKET}/${CODE}/${CODE}"

COMPANY_DIR="$DEST/$NAME"
PDF_DIR="$COMPANY_DIR/年报PDF"
mkdir -p "$COMPANY_DIR" "$PDF_DIR"

# ---------- 工具函数 ----------
log()  { echo "$1"; }
snap_new_file() {  # $1=匹配通配符, 输出新增的第一个文件 basename
  local pattern="$1"; local before after
  before=$(ls "$DOWNLOADS" 2>/dev/null | grep -iE "$pattern" | sort)
  echo "$before" > /tmp/.lx_before.txt
  return 0
}
take_new_file() {  # 与 snap_new_file 配对, 输出新增文件
  local pattern="$1"
  ls "$DOWNLOADS" 2>/dev/null | grep -iE "$pattern" | sort > /tmp/.lx_after.txt
  comm -13 /tmp/.lx_before.txt /tmp/.lx_after.txt | head -1
}
archive() {  # $1=源文件名(basename) $2=目标完整路径
  local src="$DOWNLOADS/$1"; local dst="$2"
  if [ -f "$src" ]; then
    cp "$src" "$dst" && rm "$src" && return 0
  fi
  return 1
}

OK_COUNT=0; FAIL_LIST=""

echo "=========================================="
echo " 理杏仁下载: $NAME ($MARKET$CODE)"
echo " 时间范围: $START_DATE ~ $END_DATE (${YEARS}年)"
echo " 输出目录: $COMPANY_DIR"
echo "=========================================="

# ---------- 开会话 ----------
"$CLI" browser_start_session --sessionId "$SID" --title "$NAME财报" --color green \
  --initialUrl "${PREFIX}/bs?${QUERY}" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 5 >/dev/null 2>&1
log "✅ 会话已开启"

# ============================================================
# 第一部分: 6 类 CSV 导出（标准流程）
# ============================================================
if [ "$SKIP_CSV" -eq 0 ]; then
declare -a TICKERS=("bs" "ps" "cfs" "m" "operation-revenue-constitution" "operating-data")
declare -a LABELS=("资产负债表" "利润表" "现金流量表" "财务指标" "营收构成" "经营数据")

for i in "${!TICKERS[@]}"; do
  T="${TICKERS[$i]}"; L="${LABELS[$i]}"
  echo "───── [$((i+1))/6] $L ($T) ─────"

  "$CLI" browser_go_to_url --sessionId "$SID" --url "${PREFIX}/${T}?${QUERY}" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1

  # 打开导出菜单
  "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "导出CSV" --action click >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1

  # 动态获取弹窗 index（每次都变！）
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_pop.txt 2>&1
  I1=$(grep -oE '\[[0-9]+_[a-z0-9_]+\]<input 壹' /tmp/.lx_pop.txt | grep -oE '[0-9]+_[a-z0-9_]+' | head -1)
  I2=$(grep -oE '\[[0-9]+_[a-z0-9_]+\]<a 时间横排 - 降序' /tmp/.lx_pop.txt | grep -oE '[0-9]+_[a-z0-9_]+' | head -1)

  if [ -z "$I1" ] || [ -z "$I2" ]; then
    echo "  ❌ 未找到导出选项(index 缺失)，跳过"
    FAIL_LIST="$FAIL_LIST $L"; continue
  fi

  snap_new_file "\.csv$"
  "$CLI" browser_click_element --sessionId "$SID" --index "$I1" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 1 >/dev/null 2>&1
  "$CLI" browser_click_element --sessionId "$SID" --index "$I2" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1

  NEW=$(take_new_file "\.csv$")
  if [ -n "$NEW" ]; then
    TS=$(date +%Y%m%d_%H%M%S)
    # 保留理杏仁原文件名（含报表名），补公司前缀（若缺失）
    if [[ "$NEW" == ${NAME}* ]]; then
      FINAL="$NEW"
    else
      FINAL="${NAME}_${NEW}"
    fi
    if archive "$NEW" "$COMPANY_DIR/$FINAL"; then
      echo "  ✅ $FINAL"
      OK_COUNT=$((OK_COUNT+1))
    else
      echo "  ❌ 归档失败: $NEW"; FAIL_LIST="$FAIL_LIST $L"
    fi
  else
    echo "  ❌ 未检测到下载"; FAIL_LIST="$FAIL_LIST $L"
  fi
done

# ============================================================
# 第二部分: 员工数据（DOM 提取兜底 —— UI 导出在自动化下不触发）
# ============================================================
echo "───── [7/7] 员工数据 (DOM提取) ─────"
"$CLI" browser_go_to_url --sessionId "$SID" --url "${PREFIX}/employee/all-employee?${QUERY}" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1

"$CLI" browser_eval_content_js --sessionId "$SID" --script \
"JSON.stringify(Array.from(document.querySelectorAll('table')[1].querySelectorAll('tr')).map(tr=>Array.from(tr.querySelectorAll('td,th')).map(td=>td.innerText.trim())))" \
> /tmp/.lx_emp_raw.txt 2>&1

python3 - "$NAME" "$COMPANY_DIR" <<'PY'
import json, csv, sys, os, datetime
name, outdir = sys.argv[1], sys.argv[2]
try:
    raw = open('/tmp/.lx_emp_raw.txt').read()
    obj = json.loads(raw[raw.find('{'):raw.rfind('}')+1])
    data = json.loads(obj['text'])
    years = data[0][1:]
    rows = [[r[0]] + [r[1+i*2].replace(',','') if 1+i*2 < len(r) else '' for i in range(len(years))]
            for r in data[2:] if r and r[0]]
    ts = datetime.datetime.now().strftime('%Y%m%d')
    out = os.path.join(outdir, f'{name}_员工数据_全体员工_{ts}.csv')
    with open(out,'w',newline='',encoding='utf-8-sig') as f:
        w = csv.writer(f); w.writerow(['指标']+years); w.writerows(rows)
    print(f'  ✅ {os.path.basename(out)}  ({len(rows)}个指标 × {len(years)}年)')
except Exception as e:
    print(f'  ❌ 员工数据提取失败: {e}')
PY

# ============================================================
# 第三部分: 年报 PDF（10年）
# ============================================================
if [ "$SKIP_PDF" -eq 0 ]; then
echo "───── PDF年报下载 ─────"
# 年报链接在员工页可见
"$CLI" browser_go_to_url --sessionId "$SID" --url "${PREFIX}/employee/all-employee" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1
"$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_annual.txt 2>&1

mapfile -t PDF_LINES < <(grep -oE "\[[0-9]+_[a-z0-9_]+\]<a ${NAME}[0-9]{4}年年度报告" /tmp/.lx_annual.txt | sort -u)
echo "  发现 ${#PDF_LINES[@]} 个年报链接"

for line in "${PDF_LINES[@]}"; do
  IDX=$(echo "$line" | grep -oE '^\[[0-9]+_[a-z0-9_]+\]' | tr -d '[]')
  YEAR=$(echo "$line" | grep -oE '[0-9]{4}年年度报告' | grep -oE '^[0-9]{4}')
  [ -z "$IDX" ] || [ -z "$YEAR" ] && continue

  snap_new_file "\.pdf$"
  "$CLI" browser_download_file --sessionId "$SID" --index "$IDX" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 7 >/dev/null 2>&1

  NEW=$(take_new_file "\.pdf$")
  if [ -n "$NEW" ]; then
    if archive "$NEW" "$PDF_DIR/${NAME}_${YEAR}年年度报告.pdf"; then
      echo "  ✅ ${YEAR}年年度报告.pdf"
      OK_COUNT=$((OK_COUNT+1))
    else
      echo "  ❌ 归档失败 ${YEAR}年"; FAIL_LIST="$FAIL_LIST PDF${YEAR}"
    fi
  else
    echo "  ⚠️  ${YEAR}年 未检测到下载"; FAIL_LIST="$FAIL_LIST PDF${YEAR}"
  fi
done
fi  # SKIP_PDF

fi  # SKIP_CSV

# ---------- 收尾 ----------
"$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1

echo "=========================================="
echo " 完成: $NAME"
echo " 成功 $OK_COUNT 个文件"
[ -n "$FAIL_LIST" ] && echo " 失败项:$FAIL_LIST"
echo " 目录: $COMPANY_DIR"
echo "   PDF: $(ls -1 "$PDF_DIR" 2>/dev/null | wc -l | tr -d ' ') 个"
echo "   CSV: $(ls -1 "$COMPANY_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ') 个"
echo "=========================================="
