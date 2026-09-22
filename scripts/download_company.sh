#!/usr/bin/env bash
# ============================================================
# 理杏仁 - 单公司财报完整下载
#
# 用法:
#   bash download_company.sh --name 长江电力 --market sh --code 600900 \
#        --dest "/Volumes/KIOXIA/上市公司研究/电力系统/01-发电运营（15家）" [--years 10] [--skip-pdf] [--skip-csv] \
#        [--only-years 2020,2021,2022] [--force]
#
# 幂等说明: 默认【只下载缺失或校验失败的年份】, 已存在且有效的 PDF 直接跳过。
#   补漏场景直接重跑即可, 不会重复下载。
#   --only-years : 只处理指定年份(逗号分隔); 与 --force 组合可精准换版(如 H 股→A 股)
#   --force      : 强制覆盖已有效文件(版本升级时用)
#
# A股优先规则(老板 2026-09-19 明确): A+H 两地上市公司【优先下载 A 股年报】,
#   仅当某年 A 股未收录时才回退 H 股繁体版。脚本内置该优先级, 并会标注每年用的版本。
#
# 产出:
#   {dest}/{name}/
#     ├── 年报PDF/{name}_{YYYY}年年度报告.pdf   (10年)
#     ├── 招股资料/...                            (IPO/发行文件)
#     └── 理杏仁财报/{name}_{报表}_*.csv         (7类, 10年)
# ============================================================
set -uo pipefail

# ---------- 默认参数 ----------
NAME=""; MARKET=""; CODE=""; DEST=""; YEARS=10
SKIP_PDF=0; SKIP_CSV=0; FORCE=0
ONLY_YEARS=""   # 逗号分隔, 如 2020,2021,2022; 空=处理全部年份
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
    --force) FORCE=1; shift;;
    --only-years) ONLY_YEARS="$2"; shift 2;;
    -h|--help) awk 'NR>2 && /^# =/{exit} NR>2{sub(/^# ?/,""); print}' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done
# 归一化 only-years（去掉空格, 两端补逗号便于精确匹配）
if [ -n "$ONLY_YEARS" ]; then
  ONLY_YEARS=$(printf '%s' "$ONLY_YEARS" | tr -d ' ')
  ONLY_YEARS=",${ONLY_YEARS},"
fi

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
END_DATE=$(date +%Y-%m-%d)
QUERY="fs-owner-type=consolidated&start-date=${START_DATE}&end-date=${END_DATE}"
PREFIX="${BASE}/${MARKET}/${CODE}/${CODE}"

# 下载落地垃圾治理库（未确认*.crdownload 的隔离与同内容清理）
# shellcheck source=lib_orphans.sh
source "$(cd "$(dirname "$0")" && pwd)/lib_orphans.sh"
# PDF 完整性校验库（头部 / 体积 / 尾部）
# shellcheck source=lib_pdf.sh
source "$(cd "$(dirname "$0")" && pwd)/lib_pdf.sh"

COMPANY_DIR="$DEST/$NAME"
PDF_DIR="$COMPANY_DIR/年报PDF"
CSV_DIR="$COMPANY_DIR/理杏仁财报"
mkdir -p "$COMPANY_DIR" "$PDF_DIR" "$CSV_DIR"

# ---------- 工具函数 ----------
log()  { echo "$1"; }
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
# ---------- 空壳校验（老板 2026-09-19 明确要求建检查机制）----------
# 背景: 脚本曾静默产出 3872 字节空壳 PDF(有文件名、打不开), 老板误以为"下载成功"。
# 判定必须同时看【文件头 %PDF-】和【体积】, 只看"文件存在"必然漏判。
MIN_PDF_BYTES="${MIN_PDF_BYTES:-102400}"   # 100KB; 正常年报至少 1MB+, 低于此即空壳/半截
# 实现统一在 lib_pdf.sh（全 skill 一份），这里只做薄封装，避免两处走样
fsize()     { pdf_fsize "$1"; }
md5_p()     { pdf_md5 "$1"; }
valid_pdf() { pdf_acceptable "$1" "$MIN_PDF_BYTES"; }   # $1=路径; 有效返回 0, 空壳/损坏返回 1

# ---------- 年报「名副其实性」内容校验（2026-09-20 新增，防张冠李戴）----------
# 背景（真实事故）: browser_download_file --index 用的是【跨页累积快照】里的元素索引，
#   翻页后该索引指向【当前页】的任意元素 —— 于是「下 2017 年报」实际下到了同期公告、
#   评估报告、甚至另一家公司的招股书；且旧校验只查 %PDF- 头 + 体积，32 份错件全部放行入库。
# 判据: 目标文件名含 YYYY年年度报告 → 前 20 页必须出现该年份的「年度报告/年度報告/年報」字样。
#   通过返回 0；不通过返回 1 并打印实际首页文字（便于定位下成了什么）。
annual_content_ok() {  # $1=pdf路径 $2=年份
  local p="$1" yr="$2" py=""
  # 探针遍历：必须真的能 import pymupdf，否则换下一个
  # ⚠️ 教训(2026-09-20): 旧版按路径存在就选，结果选中了无 pymupdf 的解释器 →
  #    函数走"缺工具则放行"分支 → 所有错件都被判合格，防线形同虚设。
  local cands c
  cands=("${LIXINGER_PY:-}" "$VENV/bin/python3" "$VENV/bin/python" \
         "/Users/niusl321/.workbuddy/binaries/python/envs/default/bin/python3" python3)
  for c in "${cands[@]}"; do
    [ -z "$c" ] && continue
    if { [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; } && "$c" -c 'import pymupdf' >/dev/null 2>&1; then
      py="$c"; break
    fi
  done
  if [ -z "$py" ]; then
    echo "    ⚠️ 找不到带 pymupdf 的 python → 无法校验内容，按【拒收】处理(宁缺毋滥，避免脏数据入库)"
    echo "       解决: 设 LIXINGER_PY=\"/path/to/python3\"(需已装 pymupdf)"
    return 1
  fi
  "$py" - "$p" "$yr" <<'PYEOF'
import sys, re
import pymupdf
p, yr = sys.argv[1], sys.argv[2]
try:
    d = pymupdf.open(p)
except Exception as e:
    print(f"    打开失败: {e}"); sys.exit(1)
n = len(d)
raw30 = " ".join(d[i].get_text() for i in range(min(30, n)))
head3 = re.sub(r'\s+', ' ', " ".join(d[i].get_text() for i in range(min(3, n))))
d.close()
flat = re.sub(r'[\s\u3000]', '', raw30)     # 去空白后匹配，抗「2 0 2 4」字间距设计
# ① 页数门槛（实测: 真年报 133~455 页；张冠李戴的错件 1~9 页）
if n < 50:
    print(f"    仅 {n} 页，年报通常 >100 页 → 判为公告类错件")
    sys.exit(1)
# ② 体裁黑名单（只看前 3 页；刻意不含「承诺函/决议公告」——年报目录里会出现这些词）
BLACK = re.compile(r'招股说明书|招股意向书|募集说明书|上市公告书|反馈意见|'
                   r'独立意见|跟踪信用评级|内部控制评价|法律意见书|评估报告书')
mb = BLACK.search(head3)
if mb:
    print(f"    首页体裁不是年报(命中「{mb.group(0)}」)，实际首页: {head3[:90]}")
    sys.exit(1)
# ③ 年份特征（去空格后匹配）: "2017年度报告" / "2017年年度报告" / "2 0 1 7 年 度 報 告" / "2016 年報"
cn = ''.join({'0':'〇','1':'一','2':'二','3':'三','4':'四','5':'五','6':'六','7':'七','8':'八','9':'九'}[c] for c in yr)
pat = re.compile(rf'({yr}[^0-9]{{0,4}}(年度报告|年度報告|年報))|({cn}[^0-9]{{0,4}}(年度报告|年度報告|年報))')
if pat.search(flat):
    sys.exit(0)
# ④ 宽松兜底: 前 30 页同时出现年份与年报字样（港股版式差异，如华电国际 2020）
if yr in flat and re.search(r'年度报告|年度報告|年報', flat):
    sys.exit(0)
# ⑤ 英文兜底（港股年报英文封面，如华润电力 2017）
if re.search(r'Annual\s*Report', raw30, re.I) and yr in flat:
    sys.exit(0)
print(f"    {n}页 未见「{yr}年度报告」字样，实际首页: {re.sub(r'\s+', ' ', raw30)[:90]}")
sys.exit(1)
PYEOF
}

archive() {  # $1=源文件名(basename) $2=目标完整路径
  local src="$DOWNLOADS/$1"; local dst="$2"
  if [ ! -f "$src" ]; then return 1; fi
  # ⚠️ 校验口径必须按【文件类型】分流（2026-09-20 修复回归缺陷）：
  #   PDF  → 走 valid_pdf(文件头 %PDF- + 体积≥100KB)，挡空壳/HTML 错误页
  #   非PDF(CSV 等) → 只要求非空。CSV 文件头不是 %PDF- 且通常 7~20KB，
  #                    套 PDF 校验必然被判「空壳」→ rm 丢弃。
  #   旧版对【所有】文件都调 valid_pdf，实测导致 6 类财报 CSV 整批丢失
  #   （日志: "空壳/半截文件已丢弃 …csv 19714B"）—— 修此一处即可。
  local is_pdf=0
  case "$(printf '%s' "$src" | tr 'A-Z' 'a-z')" in *.pdf) is_pdf=1;; esac
  if [ "$is_pdf" = "1" ]; then
    # 空壳一律拒收: 直接丢弃临时文件, 绝不覆盖已存在的有效目标
    if ! valid_pdf "$src"; then
      echo "  ❌ 空壳/半截文件已丢弃(未污染目标): $(basename "$src") $(fsize "$src")B"
      rm -f "$src"
      return 1
    fi
    # 【内容名副其实性】只有目标名形如「YYYY年年度报告.pdf」时才查（招股资料等跳过）
    # 可用 LX_CONTENT_CHECK=0 关闭（如遇纯英文封面的港股年报误拒时）。
    if [ "${LX_CONTENT_CHECK:-1}" = "1" ]; then
      case "$(basename "$dst")" in
        *[0-9][0-9][0-9][0-9]年年度报告.pdf)
          local _cy
          _cy=$(basename "$dst" | grep -oE '[0-9]{4}年年度报告' | grep -oE '[0-9]{4}' | head -1)
          if ! annual_content_ok "$src" "$_cy"; then
            echo "  ❌ ${_cy}年 内容不是年报(疑似张冠李戴), 已拒收入库: $(basename "$src")"
            rm -f "$src"
            return 1
          fi;;
      esac
    fi
  else
    if [ ! -s "$src" ]; then
      echo "  ❌ 空文件已丢弃(未污染目标): $(basename "$src")"
      rm -f "$src"
      return 1
    fi
  fi
  # macOS 用 -X 不带扩展属性复制, 避免在 exFAT 等外置盘生成 ._ 伴生垃圾文件
  if [ "$IS_MAC" = "1" ]; then
    cp -X "$src" "$dst" 2>/dev/null || cp "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
  if [ "$is_pdf" = "1" ]; then
    if valid_pdf "$dst"; then rm -f "$src"; return 0; fi
  else
    if [ -s "$dst" ]; then rm -f "$src"; return 0; fi
  fi
  return 1
}

# ---------- 下载目录快照（纳入 .crdownload；与 download_ipo.sh 同款修复）----------
# 教训(2026-09-19 实测): 深交所等来源的 PDF 下载完成后, 浏览器【不会改名】,
#   而是留成「未确认 NNNNNN.crdownload」。只认 *.pdf 会 ① 漏抓 ② 文件永久堆在下载目录
#   (实测一次批量堆了 73 个 / 266MB)。判定「已下载完」用【体积停止增长】(下载中会持续变大),
#   不用 %%EOF —— 实测本数据集 209 份正常 PDF 里有 22 份根本没有 %%EOF, 拿它当门槛会误判。
# ⚠️ 也不要写成 `stat -f '%z %N'`: BSD(macOS) 的 -f 是「文件系统模式」, 会输出 Inodes 之类的
#    文件系统信息而非文件名。这里复用已验证的 fsize()。
snap_dl() {
  local f lc sz
  for f in "$DOWNLOADS"/*; do
    [ -f "$f" ] || continue
    lc=$(printf '%s' "$f" | tr 'A-Z' 'a-z')
    case "$lc" in
      *.pdf|*.crdownload) ;;
      *) continue ;;
    esac
    sz=$(fsize "$f")
    printf '%s %s\n' "$sz" "$(basename "$f")"
  done | sort
}
new_pdf_line() { comm -13 "$1" "$2" 2>/dev/null | grep -iE '\.pdf$' | head -1 | sed -E 's/^[0-9]+ //'; }
new_cr_line()  { comm -13 "$1" "$2" 2>/dev/null | grep -iE '\.crdownload$' | sort -k1,1n | tail -1; }
# 等待本次下载落定(返回文件名到 DL_NEW); $1=最长轮次(每轮2s)
wait_download() {
  local maxr="${1:-25}" i cr cand
  DL_NEW=""; local prev_cr=""
  for i in $(seq 1 "$maxr"); do
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    snap_dl > /tmp/.lx_dl_after.txt
    DL_NEW=$(new_pdf_line /tmp/.lx_dl_before.txt /tmp/.lx_dl_after.txt)
    [ -n "$DL_NEW" ] && return 0
    cr=$(new_cr_line /tmp/.lx_dl_before.txt /tmp/.lx_dl_after.txt)
    if [ -n "$cr" ]; then
      cand=$(printf '%s' "$cr" | sed -E 's/^[0-9]+ //')
      # 接受条件(满足其一): ① 体积已停止增长  ② 末尾已有 %%EOF/startxref(说明写完了)
      # 均要求文件头为 %PDF-, 挡住 HTML 错误页伪装(实测 3872B 空壳)
      if pdf_head_ok "$DOWNLOADS/$cand"; then
        if [ "$cr" = "$prev_cr" ] || pdf_tail_ok "$DOWNLOADS/$cand"; then
          DL_NEW="$cand"; return 0
        fi
      fi
    fi
    prev_cr="$cr"
    if [ "$i" -eq 8 ] && [ -z "$cr" ]; then return 1; fi   # 16s 内毫无动静 → 下载未触发
  done
  return 1
}

# ---------- 自动登录（老板 2026-09-19 亲授）----------
# 理杏仁登录态会过期/丢失。此时【不要换数据源】(曾因此绕去东方财富/巨潮/上交所/新浪全部碰壁),
# 正确做法: 点击页面右上角「登录/注册」—— 账号密码已保存在浏览器里, 点一下即自动登录。
login_if_needed() {
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_login.txt 2>&1
  if ! grep -q "登录/注册" /tmp/.lx_login.txt; then
    echo "  ✅ 理杏仁已登录"
    return 0
  fi
  echo "  🔑 未登录 → 点击右上角「登录/注册」(浏览器已保存账号密码)"
  "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "登录/注册" --action click >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 4 >/dev/null 2>&1
  # 若弹出登录弹窗且有「登录」按钮(表单已由浏览器自动填充), 再点一次提交
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_login2.txt 2>&1
  if grep -qE "\[[0-9]+_[a-z0-9_]+\]<button 登录" /tmp/.lx_login2.txt; then
    "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "登录" --action click >/dev/null 2>&1
    "$CLI" browser_wait --sessionId "$SID" --seconds 5 >/dev/null 2>&1
  fi
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_login3.txt 2>&1
  if grep -q "登录/注册" /tmp/.lx_login3.txt; then
    echo "  ⚠️ 自动登录未生效 → 请在浏览器里手动登录一次后重跑"
    return 1
  fi
  echo "  ✅ 自动登录成功"
  return 0
}

OK_COUNT=0; SKIP_COUNT=0; FAIL_LIST=""; NO_DATA_LIST=""; HSHARE_LIST=""; SUSPECT_LIST=""

echo "=========================================="
echo " 理杏仁下载: $NAME ($MARKET$CODE)"
echo " 时间范围: $START_DATE ~ $END_DATE (${YEARS}年)"
echo " 输出目录: $COMPANY_DIR"
echo "=========================================="

# ---------- 开跑前治理下载目录 ----------
# 老板 2026-09-20: 要的是"别再脏我 Downloads"。
# 范围取 $DEST（数据集组目录）跨公司比对 —— 很多孤儿其实是别家已入库文件的副本, 可直接删。
echo "── 开跑前治理下载目录 ──"
delete_twin_orphans_under "$DEST"
relocate_orphans

# ---------- 开会话 ----------
# 任何异常退出都关会话, 防浏览器 tab 泄漏
cleanup() { "$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1; }

"$CLI" browser_start_session --sessionId "$SID" --title "${NAME}财报" --color green \
  --initialUrl "${PREFIX}/bs?${QUERY}" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 5 >/dev/null 2>&1
trap cleanup EXIT INT TERM
log "✅ 会话已开启"
# 登录态自检: 过期就自动点一下登录(浏览器已保存账号密码), 不要换数据源
login_if_needed || true

# ============================================================
# 第一部分: 6 类 CSV 导出（标准流程）
# ============================================================
if [ "$SKIP_CSV" -eq 0 ]; then
declare -a TICKERS=("bs" "ps" "cfs" "m" "operation-revenue-constitution" "operating-data")
declare -a LABELS=("资产负债表" "利润表" "现金流量表" "财务指标" "营收构成" "经营数据")

for i in "${!TICKERS[@]}"; do
  T="${TICKERS[$i]}"; L="${LABELS[$i]}"
  echo "───── [$((i+1))/${#TICKERS[@]}] $L ($T) ─────"

  # 幂等（老板 2026-09-20：以后不许出现重复下载）:
  #   该类报表已存在且非空 → 直接跳过, 【连页面都不打开】(省一次导航+导出)。
  #   真正要重导时显式加 --force。
  if [ "$FORCE" -eq 0 ]; then
    CSV_EXIST=""
    for _f in "$CSV_DIR"/*.csv; do
      [ -f "$_f" ] || continue
      case "$(basename "$_f")" in
        "${NAME}_${L}"*) CSV_EXIST="$(basename "$_f")"; break;;
      esac
    done
    if [ -n "$CSV_EXIST" ] && [ -s "$CSV_DIR/$CSV_EXIST" ]; then
      echo "  ⏭️  已存在(${CSV_EXIST}), 跳过(要重导加 --force)"
      SKIP_COUNT=$((SKIP_COUNT+1))
      continue
    fi
  fi

  "$CLI" browser_go_to_url --sessionId "$SID" --url "${PREFIX}/${T}?${QUERY}" >/dev/null 2>&1

  # ---------- 就绪判定（2026-09-20 新增）----------
  # 教训同公告页: 页面是异步渲染的，旧版固定等 6s 就在"控件还没出来"的状态下判断，
  #   轻则误判「未收录」(静默漏一类报表)，重则报「未找到排序选项」。
  # 现改为轮询到页面出现「数据选项」锚点为止(最多约 24s)；
  #   若始终没有 → 明确报"未渲染"，计入失败，绝不静默跳过。
  CSV_READY=0
  for _r in $(seq 1 8); do
    "$CLI" browser_wait --sessionId "$SID" --seconds 3 >/dev/null 2>&1
    "$CLI" browser_eval_content_js --sessionId "$SID" --script "document.body.innerText" \
      > /tmp/.lx_pagetext.txt 2>&1
    if grep -q '数据选项' /tmp/.lx_pagetext.txt 2>/dev/null; then CSV_READY=1; break; fi
  done
  if [ "$CSV_READY" -eq 0 ]; then
    echo "  ❌ 页面始终未渲染出「数据选项」(加载失败?), 跳过以免误判"
    FAIL_LIST="$FAIL_LIST $L[页面未渲染]"; continue
  fi

  # 该报表理杏仁是否未收录(部分公司无经营数据等) → 明确跳过, 避免误报成"找不到排序选项"
  if page_no_data; then
    echo "  ⏭️  理杏仁未收录【${L}】, 跳过(数据源缺失, 非脚本故障)"
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
    # 剥掉理杏仁导出名自带的 _YYYYMMDD_HHMMSS 时间戳后缀
    # ⚠️ 2026-09-20 修复（回归缺陷）: 旧版原样保留 → 产出
    #   `上海电力_资产负债表_合并报表_20260920_114724.csv`，与既有 15 家
    #   （`国电电力_资产负债表_合并报表.csv`，无日期）命名不一致，
    #   且违反 skill 自身规范「CSV 文件名必须稳定、不含日期」（防跨天堆积）。
    FINAL=$(printf '%s' "$FINAL" | sed -E 's/_[0-9]{8}_[0-9]{6}(\.csv)$/\1/')
    if archive "$NEW" "$CSV_DIR/$FINAL"; then
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
# 幂等: 已存在且非空 → 跳过(不打开页面)。要重导加 --force。
if [ "$FORCE" -eq 0 ] && [ -s "$CSV_DIR/${NAME}_员工数据_全体员工.csv" ]; then
  echo "  ⏭️  已存在(${NAME}_员工数据_全体员工.csv), 跳过(要重导加 --force)"
  SKIP_COUNT=$((SKIP_COUNT+1))
else
"$CLI" browser_go_to_url --sessionId "$SID" --url "${PREFIX}/employee/all-employee?${QUERY}" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1

# 取"行数最多"的表格, 不硬编码 table[1](不同公司页面表格数量可能不同)
"$CLI" browser_eval_content_js --sessionId "$SID" --script \
"JSON.stringify((function(){var ts=Array.from(document.querySelectorAll('table'));var best=null,bestN=0;for(var i=0;i<ts.length;i++){var n=ts[i].querySelectorAll('tr').length;if(n>bestN){bestN=n;best=ts[i];}}var tb=best||ts[1];return Array.from(tb.querySelectorAll('tr')).map(function(tr){return Array.from(tr.querySelectorAll('td,th')).map(function(td){return td.innerText.trim()})})})())" \
> /tmp/.lx_emp_raw.txt 2>&1

rm -f /tmp/.lx_emp_fail
python3 - "$NAME" "$CSV_DIR" <<'PY'
import json, csv, sys, os, datetime
name, outdir = sys.argv[1], sys.argv[2]
try:
    raw = open('/tmp/.lx_emp_raw.txt').read()
    obj = json.loads(raw[raw.find('{'):raw.rfind('}')+1])
    data = json.loads(obj['text'])
    years = data[0][1:]
    rows = [[r[0]] + [r[1+i*2].replace(',','') if 1+i*2 < len(r) else '' for i in range(len(years))]
            for r in data[2:] if r and r[0]]
    # 命名对齐老板规范(无日期, 覆盖式): 带日期会导致跨天重复堆积
    out = os.path.join(outdir, f'{name}_员工数据_全体员工.csv')
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
fi   # 员工数据幂等守卫

fi  # SKIP_CSV  ← CSV部分到此结束(PDF独立在后, 故 --skip-csv 不会连带跳过PDF)

# ============================================================
# 第三部分: 年报 PDF（10年）—— 独立于 CSV 部分
# ============================================================
if [ "$SKIP_PDF" -eq 0 ]; then
echo "───── PDF年报下载 ─────"
# 年报在「公告」页。
# 🔴 2026-09-20 重大修正：**不要再用 `search-key=年度报告`** —— 实测该筛选已失效：
#   页面直接显示「没有相关数据。」，pdf 链接数 0 → 脚本「发现 0 个年报链接」→
#   **静默漏抓整段年报**（而且不报错，极易被误判成"数据源没有"）。
#   对照实测同一时刻：`announcement-type=all` 正常（pdf 链接 100 个）。
#   好在下方本来就有【按标题正则筛年报】的逻辑（FULL_RE/PLAIN_RE），
#   所以取全部公告 + 用正则挑年报即可，不再依赖站点的 search-key 筛选。
ANN_URL="${PREFIX}/announcement?announcement-type=all"

# ---------- 🔴 换一个【以公告页为初始页】的全新会话来做年报采集（2026-09-20 修复）----------
# 实测教训: 在已开着的会话里做【站内路由跳转】(browser_go_to_url)到公告页时，
#   公告列表**根本不会渲染** —— JS 查 pdf 链接数恒为 0，等 42s 无效、
#   browser_tab_reload 硬刷新也无效、browser_tab_open 后不切游标同样无效。
# 对照实测: 用 --initialUrl 直接以公告页【新开会话】立刻正常。
#   → 理杏仁是 SPA，站内路由切换会把页面搞成"半渲染"状态，必须走全新加载。
# 做法: 关掉 CSV 阶段的会话（它已完成使命），把 SID 换成新会话 id，
#   后面所有代码继续用 $SID → 无需改任何调用点；trap 也会正确关掉新会话。
"$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1
SID="${SID}-ann"
"$CLI" browser_start_session --sessionId "$SID" --title "${NAME}年报公告" --color cyan \
  --initialUrl "$ANN_URL" >/dev/null 2>&1

# ---------- 就绪判定（2026-09-20 新增，修「发现 0 个年报链接」）----------
# 实测教训: 公告列表是【异步渲染】的。旧版固定等 5s 就开始采集,
#   而该页（华能国际 55 条）要 12~14s 才把列表渲染出来 —— 于是快照全是空的,
#   日志打成「发现 0 个年报链接, 跳过PDF阶段」→ 静默漏抓整段年报。
#   ⚠️ 而且它**不报错**，只看日志很容易以为是"数据源没有"。
# 现改为: 轮询 JS 里的 pdf 链接数, 连续两次一致才认为就绪(最多约 40s), 再开始分段滚动采集。
ann_pdf_count() {
  "$CLI" browser_eval_content_js --sessionId "$SID" \
    --script "(()=>'ANNCNT='+[...document.querySelectorAll('a')].filter(x=>/\.pdf/i.test(x.getAttribute('href')||'')).length)()" 2>/dev/null \
    | grep -oE 'ANNCNT=[0-9]+' | head -1 | cut -d= -f2
}
ann_ready() {
  local i cur prev="" stable=0 waited=0
  for i in $(seq 1 14); do
    cur=$(ann_pdf_count)
    if [ -n "$cur" ] && [ "$cur" -gt 0 ] 2>/dev/null; then
      if [ "$cur" = "$prev" ]; then stable=$((stable+1)); else stable=0; fi
      prev="$cur"
      if [ "$stable" -ge 1 ]; then
        echo "  ⏱️  公告列表就绪(等待约 ${waited}s, 页面 pdf 链接 ${cur} 个)"
        return 0
      fi
    fi
    "$CLI" browser_wait --sessionId "$SID" --seconds 3 >/dev/null 2>&1
    waited=$((waited+3))
  done
  echo "  ⏱️  等待 ${waited}s 仍未确认公告列表就绪(继续尝试采集)"
  return 1
}
ann_ready || true

# ---------- 🔴 逐页采集（2026-09-20 修复：公告列表是"最新在前 + 分页"）----------
# 实测: 华能国际公告共 24 页，【一页约等于一年】—— 第1页 2025 年、第2页 2024 年 ……
#   旧版只采第 1 页 → 「发现 1 个年报链接, 覆盖年份: 2025」→ **静默漏抓 9 年**。
# 分页条 DOM: `ul.pagination` → 末项 `li.page-item > span.page-link` 文本为 `›`（下一页）。
#   点击实测有效(两种方式都行): `browser_find_and_act --by text --value "›" --action click`，
#   或用 JS 点最后一个 li（页码 1→2→3 均验证通过）。
# ⚠️ 页面上的「年度报告」分类按钮点了**不生效**（实测年份不变），别指望它筛选。
# 停止条件（任一）: ① 已覆盖到 START_YEAR（够用了，不用翻满）② 到 MAX_PAGES ③ 点不动了
MAX_PAGES="${MAX_PAGES:-16}"
START_YEAR=$(( $(date +%Y) - YEARS ))   # 翻页停止判据要用, 必须在采集前算出来
ann_active_page() {
  "$CLI" browser_eval_content_js --sessionId "$SID" \
    --script "(()=>{const a=document.querySelector('ul.pagination li.active');return 'PAGE='+(a?a.textContent.trim():'-')})()" 2>/dev/null \
    | grep -oE 'PAGE=[0-9]+' | head -1 | cut -d= -f2
}
# 滚动整页并合并快照: 步长按视口重叠覆盖, 范围用实际页高(不再写死 12000)
collect_page() {
  local h pos step=700
  h=$("$CLI" browser_eval_content_js --sessionId "$SID" --script "document.body.scrollHeight" 2>/dev/null \
      | grep -oE '[0-9]+' | head -1)
  [ -z "$h" ] && h=12000
  pos=0
  while [ "$pos" -le "$h" ]; do
    "$CLI" browser_eval_content_js --sessionId "$SID" \
      --script "window.scrollTo(0,${pos});'ok'" >/dev/null 2>&1
    "$CLI" browser_wait --sessionId "$SID" --seconds 1 >/dev/null 2>&1
    "$CLI" browser_snapshot --sessionId "$SID" >> /tmp/.lx_annual.txt 2>&1
    pos=$((pos+step))
  done
}
: > /tmp/.lx_annual.txt
PAGE_NO=1
while [ "$PAGE_NO" -le "$MAX_PAGES" ]; do
  collect_page
  # 已覆盖到起始年份 → 收工(不必翻满)
  OLDY=$( { cat /tmp/.lx_annual.txt; } \
          | grep -oE '[0-9]{4}[[:space:]]*年?年度报告' | grep -oE '[0-9]{4}' | sort -n | head -1 )
  if [ -n "$OLDY" ] && [ "$OLDY" -le "$START_YEAR" ] 2>/dev/null; then
    echo "  ✅ 已覆盖到 ${OLDY}年(需 ${START_YEAR}年起)，停止翻页"
    break
  fi
  BEF=$(ann_active_page)
  "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "›" --action click >/dev/null 2>&1
  AFT=""; CHANGED=0
  for _w in 1 2 3 4 5 6; do
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    AFT=$(ann_active_page)
    if [ -n "$AFT" ] && [ "$AFT" != "$BEF" ]; then CHANGED=1; break; fi
  done
  if [ "$CHANGED" -eq 0 ]; then
    echo "  ⏭️  已到最后一页(第 ${BEF:-?} 页)，停止翻页"
    break
  fi
  PAGE_NO=$((PAGE_NO+1))
  echo "  📄 翻到第 ${AFT} 页(已采分钟级累积快照)"
done
echo "  📄 共采集 ${PAGE_NO} 页"

# 精确匹配年报链接（排除「摘要」「半年度报告」）
# ⚠️ 关键教训(2026-09-19 实测, 华能国际 sh600011):
#   理杏仁上同一份年报可能有两个条目 —— A股正文标题带后缀「…年度报告全文」,
#   而 H 股版本标题为「华能国际H股2022年年度报告」(无后缀, 繁体)。
#   旧正则写死 [0-9]{4}年年度报告/> (要求"年度报告"后紧跟结束符) 会同时踩两个坑:
#     ① 「…全文」被排除 → 该年份整年漏抓(实测漏 2023/2024);
#     ② 反而只抓到 H 股繁体版(实测 2022 抓成 12.2MB 的 H 股版, A股全文仅 6.7MB)。
#   正确做法: 优先取「全文」版, 无「全文」版时才回退到无后缀版。
# 公司名部分仍用 [^/>]* 通配(兼容简称/全称混用, 如 中国核电 vs 中国核能电力股份有限公司)
FULL_RE="\[[0-9]+_[a-z0-9_]+\]<a [^/>]*[0-9]{4}[[:space:]]*年?年度报告全文/>points to a pdf"
PLAIN_RE="\[[0-9]+_[a-z0-9_]+\]<a [^/>]*[0-9]{4}[[:space:]]*年?年度报告/>points to a pdf"
grep -oE "$FULL_RE"  /tmp/.lx_annual.txt | sort -u > /tmp/.lx_pdf_full.txt
grep -oE "$PLAIN_RE" /tmp/.lx_annual.txt | sort -u > /tmp/.lx_pdf_plain.txt
# 候选年份 = 两轮命中合并去重(天然去掉多屏重复, 不再需要 DONE_YEARS 守卫)
YEARS_ALL=$( { cat /tmp/.lx_pdf_full.txt /tmp/.lx_pdf_plain.txt; } \
             | grep -oE '[0-9]{4}[[:space:]]*年?年度报告' | grep -oE '[0-9]{4}' | sort -u )
echo "  发现 $(cat /tmp/.lx_pdf_full.txt /tmp/.lx_pdf_plain.txt | wc -l | tr -d ' ') 个年报链接, 覆盖年份: $(echo $YEARS_ALL | tr '\n' ' ')"

START_YEAR=$(( $(date +%Y) - YEARS ))

# ---------- 🔴 覆盖度自检（2026-09-20 新增，防止"静默只抓到一年"）----------
# 背景: 公告列表是【最新在前 + 分页】的。实测 2026-09-20 出现「发现 1 个年报链接,
#   覆盖年份: 2025」—— 2016~2024 全在后续页, 脚本却会当作"已最新"照常收工。
#   这类静默漏抓最危险: 日志看着正常, 数据却缺 9 年。
# 判据: 拿【已在库的年份】跟【本次发现的年份】比 —— 库里有而这次没发现的, 就是漏抓。
#   （首次下载时库为空, 无法用此判据; 此时若发现年份明显少于 --years 也会提示。）
LIBYEARS=$(ls -1 "$PDF_DIR" 2>/dev/null | grep -oE '[0-9]{4}[[:space:]]*年?年度报告' | grep -oE '[0-9]{4}' | sort -u)
MISSING_YEARS=""
if [ -n "$LIBYEARS" ]; then
  for _y in $LIBYEARS; do
    case " $(echo $YEARS_ALL | tr '\n' ' ') " in
      *" $_y "*) : ;;
      *) MISSING_YEARS="$MISSING_YEARS $_y" ;;
    esac
  done
  if [ -n "$MISSING_YEARS" ]; then
    echo "  🔴 覆盖度告警: 库内已有但本次【未发现】的年份:${MISSING_YEARS}"
    echo "       极可能是公告列表分页/筛选失效导致抓不全 → 请勿当作「已是最新」!"
    echo "       排查方向: 公告页是否分页、年度报告分类筛选是否可用(详见 SKILL.md「已知未决问题」)"
  fi
fi

# bash 3.2 + set -u 下空数组展开会崩(unbound variable), 必须守卫
if [ -z "$YEARS_ALL" ]; then
  echo "  ⚠️  公告页未匹配到年报链接, 跳过PDF阶段(不中断后续)"
  echo "      ⚠️ 注意: 这可能是【列表没渲染出来/筛选失效】而不是数据源没有 ——"
  echo "         2026-09-20 实测 search-key 筛选已失效(页面显示「没有相关数据」), 已改用 type=all;"
  echo "         若反复出现请检查公告页结构是否又变"
else
HSHARE_LIST=""   # 记录"只有 H 股版可用"的年份, 汇总时告警
for YEAR in $YEARS_ALL; do
  # --only-years 过滤（精准补漏/换版, 避免整家重跑）
  if [ -n "$ONLY_YEARS" ]; then
    case "$ONLY_YEARS" in
      *",${YEAR},"*) : ;;
      *) continue ;;
    esac
  fi
  if [ "$YEAR" -lt "$START_YEAR" ]; then
    echo "  ⏭️  ${YEAR}年(超出${YEARS}年范围, 起点${START_YEAR}) 跳过"
    continue
  fi

  # 版本优先级（老板 2026-09-19 要求: A+H 公司优先 A 股）:
  #   ① A股「…年度报告全文」(简体正文)  →  ② A股无后缀版  →  ③ 才轮到 H股繁体版
  # 华能国际 2020 同时有「H股2020年年度报告」与「2020年年度报告」两个条目,
  # 旧逻辑 sort 后 head -1 抓到排前的 H 股版(实测 2020/2021/2022 三年均为繁体版)
  VER=""
  LINE=$(grep -E "${YEAR}[[:space:]]*年?年度报告全文" /tmp/.lx_pdf_full.txt | head -1)
  [ -n "$LINE" ] && VER="A股全文"
  if [ -z "$LINE" ]; then
    LINE=$(grep -E "${YEAR}[[:space:]]*年?年度报告" /tmp/.lx_pdf_plain.txt | grep -vE "H[ ]?股" | head -1)
    [ -n "$LINE" ] && VER="A股"
  fi
  if [ -z "$LINE" ]; then
    LINE=$(grep -E "${YEAR}[[:space:]]*年?年度报告" /tmp/.lx_pdf_plain.txt | head -1)
    [ -n "$LINE" ] && VER="H股繁体"
  fi
  IDX=$(echo "$LINE" | grep -oE '^\[[0-9]+_[a-z0-9_]+\]' | tr -d '[]')
  if [ -z "$IDX" ]; then
    continue
  fi

  # 幂等: 目标已存在且校验通过 → 跳过, 绝不重复下载有效文件。
  # (老板 2026-09-19 明确要求: 补漏只下缺失/损坏的年份, 不许整家重下)
  DST="$PDF_DIR/${NAME}_${YEAR}年年度报告.pdf"
  if [ "$FORCE" -eq 0 ] && valid_pdf "$DST"; then
    echo "  ⏭️  ${YEAR}年 已存在且校验通过($(fsize "$DST")B), 跳过"
    SKIP_COUNT=$((SKIP_COUNT+1)); continue
  fi
  if [ -f "$DST" ]; then
    # 区分两种情况, 别把 --force 的版本升级误报成"文件损坏"
    if valid_pdf "$DST"; then
      echo "  🔄 ${YEAR}年 --force 覆盖现有有效文件($(fsize "$DST")B)"
    else
      echo "  🔄 ${YEAR}年 现有文件损坏($(fsize "$DST")B), 重新下载"
    fi
    rm -f "$DST"   # 先清掉旧文件, 避免下载失败时留下假文件
  fi

  # 轮询等待(最多50s/次): 大PDF + 「未确认 NNNNNN.crdownload」定型都需要时间
  # 实测(2026-09-19): 每个会话的【第一条】下载经常不触发(浏览器需热身) → 失败自动重试 3 次
  NEW=""; ATTEMPT=0
  while [ "$ATTEMPT" -lt 3 ]; do
    ATTEMPT=$((ATTEMPT+1))
    snap_dl > /tmp/.lx_dl_before.txt
    "$CLI" browser_download_file --sessionId "$SID" --index "$IDX" >/dev/null 2>&1
    if wait_download 25; then NEW="$DL_NEW"; break; fi
    NEW=""
    [ "$ATTEMPT" -lt 3 ] && echo "  🔁 ${YEAR}年 未触发下载, 重试(${ATTEMPT}/3)…"
  done
  if [ -n "$NEW" ]; then
    if archive "$NEW" "$DST"; then
      echo "  ✅ ${YEAR}年年度报告.pdf  [$VER]"
      [ "$VER" = "H股繁体" ] && HSHARE_LIST="$HSHARE_LIST $YEAR"
      OK_COUNT=$((OK_COUNT+1))
      delete_twin_orphans "$DST"   # 顺手清掉与它同内容的「未确认*.crdownload」孤儿
      # 入库后复查尾部完整性: 缺 %%EOF/startxref → 疑似截断。只告警不拒收
      # （拒收会导致反复重下, 正是老板不想要的）。
      if ! pdf_tail_ok "$DST"; then
        echo "  ⚠️  ${YEAR}年 尾部无 %%EOF/startxref, 疑似截断(已入库, 请复核)"
        SUSPECT_LIST="$SUSPECT_LIST PDF${YEAR}"
      fi
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

# 收尾清理: 目标目录 ._ AppleDouble 垃圾文件
# ⚠️ 用自带 python 删除, 不用 dot_clean —— dot_clean 是外部二进制, 沙箱下会被拦截(unlink 被拒)
if command -v python3 >/dev/null 2>&1; then
python3 - "$COMPANY_DIR" <<'PY'
import os, sys
n1 = 0
for root, dirs, files in os.walk(sys.argv[1]):
    for nm in list(files) + list(dirs):
        if nm.startswith('._'):
            try:
                os.remove(os.path.join(root, nm)); n1 += 1
            except Exception:
                pass
if n1: print(f'  🧹 清理 ._ 垃圾文件 {n1} 个')
PY
fi

# 收尾治理下载目录: 把剩余的「未确认*.crdownload」一律【隔离】出他的下载目录（移动, 不删）
# 同内容的已在"归档时"逐个清过, 这里只需隔离。
# 注: 旧版按 mtime 删本次会话产生的 *.crdownload —— 会误伤老板同时进行的正常下载, 已废弃。
relocate_orphans
LEFT=$(list_orphans | grep -c . || true); LEFT=${LEFT:-0}
[ "$LEFT" -gt 0 ] && echo " ⚠️ 仍有 ${LEFT} 个「未确认*.crdownload」留在下载目录(治理未生效), 请检查"

echo "=========================================="
echo " 完成: $NAME"
echo " 成功 $OK_COUNT 个文件"
[ "$SKIP_COUNT" -gt 0 ] && echo " ⏭️跳过(已存在且有效) $SKIP_COUNT 个"
[ -n "$FAIL_LIST" ] && echo " ❌失败项:$FAIL_LIST"
[ -n "$NO_DATA_LIST" ] && echo " ⏭️理杏仁未收录(数据源缺失,非故障):$NO_DATA_LIST"
[ -n "$HSHARE_LIST" ] && echo " ⚠️这些年份仅H股可用(A股未收录,繁体版):$HSHARE_LIST"
[ -n "$SUSPECT_LIST" ] && echo " ⚠️疑似截断(尾部无 %%EOF/startxref, 请复核):$SUSPECT_LIST"
echo " 目录: $COMPANY_DIR"
echo "   PDF: $(ls -1 "$PDF_DIR" 2>/dev/null | wc -l | tr -d ' ') 个"
echo "   CSV: $(ls -1 "$CSV_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ') 个"
echo "=========================================="
