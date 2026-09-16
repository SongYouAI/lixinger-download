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
  IS_MAC=1
  START_DATE=$(date -v-${YEARS}y +%Y-%m-%d)
else
  IS_MAC=0
  START_DATE=$(date -d "${YEARS} years ago" +%Y-%m-%d)
fi
SESSION_START=$(date +%s)   # 用于收尾时精准清理"本次产生的"临时文件
END_DATE=$(date +%Y-%m-%d)
QUERY="fs-owner-type=consolidated&start-date=${START_DATE}&end-date=${END_DATE}"
PREFIX="${BASE}/${MARKET}/${CODE}/${CODE}"

COMPANY_DIR="$DEST/$NAME"
PDF_DIR="$COMPANY_DIR/年报PDF"
mkdir -p "$COMPANY_DIR" "$PDF_DIR"

# ---------- 工具函数 ----------
log()  { echo "$1"; }
escape_re() {  # 转义正则元字符, 让公司名可安全用于 grep -E(防 ( ) . * 等注入)
  printf '%s' "$1" | sed 's/[][\.*^$()+?{}|]/\\&/g'
}
# 判定报表页是否"无数据": 只看「数据选项」锚点后 300 字
# 不能全文 grep "无数据" —— 页面他处(导航栏/指标说明)出现该词会误判整张表未收录
page_no_data() {
  python3 - <<'PY' 2>/dev/null
import json, re
seg = ''
try:
    raw = open('/tmp/.lx_pagetext.txt', encoding='utf-8', errors='replace').read()
    m = re.search(r'"text":\s*"((?:[^"\\]|\\.)*)"', raw, re.S)
    t = json.loads('"' + m.group(1) + '"') if m else ''
    i = t.find('数据选项')
    seg = t[i:i+300] if i >= 0 else ''
except Exception:
    pass
raise SystemExit(0 if '无数据' in seg else 1)
PY
}
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
    # macOS 用 -X 不带扩展属性复制, 避免在 exFAT 等外置盘生成 ._ 伴生垃圾文件
    if [ "$IS_MAC" = "1" ]; then
      cp -X "$src" "$dst" 2>/dev/null || cp "$src" "$dst"
    else
      cp "$src" "$dst"
    fi
    if [ -f "$dst" ]; then rm -f "$src"; return 0; fi
  fi
  return 1
}

OK_COUNT=0; FAIL_LIST=""; NO_DATA_LIST=""

echo "=========================================="
echo " 理杏仁下载: $NAME ($MARKET$CODE)"
echo " 时间范围: $START_DATE ~ $END_DATE (${YEARS}年)"
echo " 输出目录: $COMPANY_DIR"
echo "=========================================="

# ---------- 公司名正则转义 ----------
NAME_RE=$(escape_re "$NAME")

# ---------- 开会话 ----------
# 任何异常退出都关会话, 防浏览器 tab 泄漏
cleanup() { "$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1; }

"$CLI" browser_start_session --sessionId "$SID" --title "$NAME财报" --color green \
  --initialUrl "${PREFIX}/bs?${QUERY}" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 5 >/dev/null 2>&1
trap cleanup EXIT INT TERM
log "✅ 会话已开启"

# ============================================================
# 第一部分: 6 类 CSV 导出（标准流程）
# ============================================================
if [ "$SKIP_CSV" -eq 0 ]; then
declare -a TICKERS=("bs" "ps" "cfs" "m" "operation-revenue-constitution" "operating-data")
declare -a LABELS=("资产负债表" "利润表" "现金流量表" "财务指标" "营收构成" "经营数据")

for i in "${!TICKERS[@]}"; do
  T="${TICKERS[$i]}"; L="${LABELS[$i]}"
  echo "───── [$((i+1))/${#TICKERS[@]}] $L ($T) ─────"

  "$CLI" browser_go_to_url --sessionId "$SID" --url "${PREFIX}/${T}?${QUERY}" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1

  # 该报表理杏仁是否未收录(部分公司无经营数据等) → 明确跳过, 避免误报成"找不到排序选项"
  "$CLI" browser_eval_content_js --sessionId "$SID" --script "document.body.innerText" \
    > /tmp/.lx_pagetext.txt 2>&1
  if page_no_data; then
    echo "  ⏭️  理杏仁未收录【$L】, 跳过(数据源缺失, 非脚本故障)"
    NO_DATA_LIST="$NO_DATA_LIST $L"; continue
  fi

  # 打开导出菜单
  "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "导出CSV" --action click >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1

  # 动态获取弹窗 index（每次都变！）
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_pop.txt 2>&1
  I1=$(grep -oE '\[[0-9]+_[a-z0-9_]+\]<input 壹' /tmp/.lx_pop.txt | grep -oE '[0-9]+_[a-z0-9_]+' | head -1)
  I2=$(grep -oE '\[[0-9]+_[a-z0-9_]+\]<a 时间横排 - 降序' /tmp/.lx_pop.txt | grep -oE '[0-9]+_[a-z0-9_]+' | head -1)

  if [ -z "$I2" ]; then
    echo "  ❌ 未找到排序选项(时间横排-降序)，跳过"
    FAIL_LIST="$FAIL_LIST $L"; continue
  fi

  snap_new_file "\.csv$"
  if [ "$T" = "operating-data" ]; then
    # 经营数据弹窗无「壹」单位选项(单位固定)，直接点排序即触发下载
    [ -z "$I1" ] && echo "  (经营数据无需选单位, 直接导出)"
    "$CLI" browser_click_element --sessionId "$SID" --index "$I2" >/dev/null 2>&1
  else
    if [ -z "$I1" ]; then
      echo "  ❌ 未找到单位选项(壹)，跳过"
      FAIL_LIST="$FAIL_LIST $L"; continue
    fi
    "$CLI" browser_click_element --sessionId "$SID" --index "$I1" >/dev/null 2>&1
    "$CLI" browser_wait --sessionId "$SID" --seconds 1 >/dev/null 2>&1
    "$CLI" browser_click_element --sessionId "$SID" --index "$I2" >/dev/null 2>&1
  fi
  # 轮询等待(与PDF一致): 固定等6s在网络慢时会误判"未检测到下载"
  NEW=""
  for _c in 1 2 3 4 5 6 7 8; do
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    NEW=$(take_new_file "\.csv$")
    [ -n "$NEW" ] && break
  done
  if [ -n "$NEW" ]; then
    # 保留理杏仁原文件名（含报表名），补公司前缀（若缺失）
    # 用 case 而非 [[ x == ${NAME}* ]], 避免公司名含 glob 元字符时被当通配符
    case "$NEW" in
      "${NAME}"*) FINAL="$NEW";;
      *)          FINAL="${NAME}_${NEW}";;
    esac
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

# 取"行数最多"的表格, 不硬编码 table[1](不同公司页面表格数量可能不同)
"$CLI" browser_eval_content_js --sessionId "$SID" --script \
"JSON.stringify((function(){var ts=Array.from(document.querySelectorAll('table'));var best=null,bestN=0;for(var i=0;i<ts.length;i++){var n=ts[i].querySelectorAll('tr').length;if(n>bestN){bestN=n;best=ts[i];}}var tb=best||ts[1];return Array.from(tb.querySelectorAll('tr')).map(function(tr){return Array.from(tr.querySelectorAll('td,th')).map(function(td){return td.innerText.trim()})})})())" \
> /tmp/.lx_emp_raw.txt 2>&1

rm -f /tmp/.lx_emp_fail
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
    open('/tmp/.lx_emp_fail','w').write('1')
PY
# 员工数据失败要计入统计, 不能静默(否则最终报告显示"成功"但文件缺失)
if [ -f /tmp/.lx_emp_fail ]; then
  rm -f /tmp/.lx_emp_fail
  FAIL_LIST="$FAIL_LIST 员工数据"
fi

fi  # SKIP_CSV  ← CSV部分到此结束(PDF独立在后, 故 --skip-csv 不会连带跳过PDF)

# ============================================================
# 第三部分: 年报 PDF（10年）—— 独立于 CSV 部分
# ============================================================
if [ "$SKIP_PDF" -eq 0 ]; then
echo "───── PDF年报下载 ─────"
# 年报在「公告」页: 用 search-key 筛选年度报告(排除摘要/半年度/季报)
# 注意: 员工页/经营数据页快照里只有各类临时公告, 不含年度报告, 必须用公告筛选页
ANN_URL="${PREFIX}/announcement?search-key=%E5%B9%B4%E5%BA%A6%E6%8A%A5%E5%91%8A"
"$CLI" browser_go_to_url --sessionId "$SID" --url "$ANN_URL" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 5 >/dev/null 2>&1
# 分段滚动 + 多次快照合并:
# snapshot 只捕获"视口内"元素, 单次滚到底会让视口停在页面底部,
# 顶部/中间的年报就会漏掉(年报条目多的公司必踩) → 必须分段滚动逐屏采集
"$CLI" browser_scroll_to_bottom --sessionId "$SID" >/dev/null 2>&1  # 先触发懒加载
"$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
: > /tmp/.lx_annual.txt
for _pos in 0 700 1400 2100 2800 3500 4200 4900; do
  "$CLI" browser_eval_content_js --sessionId "$SID" \
    --script "window.scrollTo(0,${_pos});'ok'" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 1 >/dev/null 2>&1
  "$CLI" browser_snapshot --sessionId "$SID" >> /tmp/.lx_annual.txt 2>&1
done

# 精确匹配: 公司名+YYYY年年度报告 (排除"摘要"/"半年度")
PDF_LINES=()
while IFS= read -r line; do
  [ -n "$line" ] && PDF_LINES+=("$line")
# 兼容简称/全称混用: 同一公司不同年份的公告标题可能用简称(中国核电)也可能用全称(中国核能电力股份有限公司),
# 故公司名部分用 [^/>]* 通配, 不能写死 ${NAME} —— 否则全称标题的年份会整年漏掉(实测漏 2021/2022/2024)
# 靠 "YYYY年年度报告/>points to a pdf"(紧邻 />) 同时排除「摘要」与「半年度报告」
done < <(grep -oE "\[[0-9]+_[a-z0-9_]+\]<a [^/>]*[0-9]{4}年年度报告/>points to a pdf" /tmp/.lx_annual.txt | sort -u)
echo "  发现 ${#PDF_LINES[@]} 个年报链接"

START_YEAR=$(( $(date +%Y) - YEARS ))
# bash 3.2 + set -u 下空数组展开会崩(unbound variable), 必须守卫
if [ "${#PDF_LINES[@]}" -eq 0 ]; then
  echo "  ⚠️  公告页未匹配到年报链接, 跳过PDF阶段(不中断后续)"
else
DONE_YEARS=""
for line in "${PDF_LINES[@]}"; do
  IDX=$(echo "$line" | grep -oE '^\[[0-9]+_[a-z0-9_]+\]' | tr -d '[]')
  YEAR=$(echo "$line" | grep -oE '[0-9]{4}年年度报告' | grep -oE '[0-9]{4}')
  if [ -z "$IDX" ] || [ -z "$YEAR" ]; then
    continue
  fi
  # 按年份去重: 多屏采集时同一年报可能在多个视口重复出现
  case " $DONE_YEARS " in
    *" $YEAR "*) continue;;
  esac
  DONE_YEARS="$DONE_YEARS $YEAR"
  if [ "$YEAR" -lt "$START_YEAR" ]; then
    echo "  ⏭️  ${YEAR}年(超出${YEARS}年范围, 起点${START_YEAR}) 跳过"
    continue
  fi

  snap_new_file "\.pdf$"
  "$CLI" browser_download_file --sessionId "$SID" --index "$IDX" >/dev/null 2>&1
  # 轮询等待: 大PDF超过固定等待, 每2s检测一次, 最多20s
  NEW=""
  for _w in 1 2 3 4 5 6 7 8 9 10; do
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    NEW=$(take_new_file "\.pdf$")
    [ -n "$NEW" ] && break
  done
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
fi  # PDF_LINES 非空守卫
fi  # SKIP_PDF

# ---------- 收尾 ----------
"$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1

# 收尾清理: ①目标目录 ._ AppleDouble 垃圾文件  ②下载目录本次产生的 .crdownload 临时残留
# ⚠️ 用自带 python 删除, 不用 dot_clean —— dot_clean 是外部二进制, 沙箱下会被拦截(unlink 被拒)
if command -v python3 >/dev/null 2>&1; then
python3 - "$COMPANY_DIR" "$DOWNLOADS" "$SESSION_START" <<'PY'
import os, sys, glob
cdir, ddir, start = sys.argv[1], sys.argv[2], int(sys.argv[3])
n1 = 0
for root, dirs, files in os.walk(cdir):
    for nm in list(files) + list(dirs):
        if nm.startswith('._'):
            try:
                os.remove(os.path.join(root, nm)); n1 += 1
            except Exception:
                pass
n2 = 0
for f in glob.glob(os.path.join(ddir, '*.crdownload')):
    try:
        if os.path.getmtime(f) >= start - 5:
            os.remove(f); n2 += 1
    except Exception:
        pass
if n1: print(f'  🧹 清理 ._ 垃圾文件 {n1} 个')
if n2: print(f'  🧹 清理下载临时残留 {n2} 个')
PY
fi

echo "=========================================="
echo " 完成: $NAME"
echo " 成功 $OK_COUNT 个文件"
[ -n "$FAIL_LIST" ] && echo " ❌失败项:$FAIL_LIST"
[ -n "$NO_DATA_LIST" ] && echo " ⏭️理杏仁未收录(数据源缺失,非故障):$NO_DATA_LIST"
echo " 目录: $COMPANY_DIR"
echo "   PDF: $(ls -1 "$PDF_DIR" 2>/dev/null | wc -l | tr -d ' ') 个"
echo "   CSV: $(ls -1 "$COMPANY_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ') 个"
echo "=========================================="
