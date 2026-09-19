#!/usr/bin/env bash
# ============================================================
# 理杏仁 - 招股/发行文件（IPO 分类）下载
#
# 用法:
#   bash download_ipo.sh --name 华能水电 --market sh --code 600025 \
#        --dest "/Volumes/KIOXIA/上市公司研究/电力系统/01-发电运营（15家）"
#
# ⚠️ 为何必须走 IPO 分类（不要用 search-key）:
#   用 search-key=招股说明书 只能命中标题里写死"招股说明书"的文件,
#   会漏掉大量叫「招股意向书」的文件(老公司 IPO 时用的是"意向书")。
#   实测: search-key 只命中少数几家; IPO 分类能覆盖各公司全部发行文件。
#
# ⚠️ 各家 IPO 分类条目数差异极大(2026-09-19 实测, 非故障):
#   三峡能源 22 / 中国核电 15 / 国投电力 5 / 国电电力 4 /
#   长江电力 3 / 华能国际 2 / 浙能电力 2 / 龙源电力 2 / 华润电力 0
#   老牌公司(2001 年上市)往往只有当年那 1~2 份招股意向书;
#   纯港股公司(华润电力/中国电力)IPO 分类为 0 条。
#
# 产出: {dest}/{name}/招股资料/{name}_{标题去掉公司名前缀}.pdf
# 幂等: 已存在且校验通过的文件跳过, 不重复下载。
#
# 🔴🔴 硬规则（老板 2026-09-19 明确要求）：**禁止全量灌 IPO 分类** 🔴🔴
#   老板原话:「IPO 只留我现在正在要的这种，你不要再重复下载了。
#              有些 IPO 的内容不是我需要的，我自己已经做过筛选。」
#   IPO 分类下条目很多（实测 17 家合计 153 条），但**大部分不是老板要的**：
#   发行公告 / 询价·中签·摇号公告 / 投资风险特别公告 / 保荐书 / 法律意见书 /
#   限售股上市流通公告 / 募集资金账户公告 …… 这些程序性文件一律不要。
#   👉 因此本脚本**必须**用 --include 指定要抓的类型，否则直接报错退出；
#      只有显式加 --all 才允许全量（正常情况下不该用）。
#   例：只看招股书类 →  --include 招股说明书,招股意向书
# ============================================================
set -uo pipefail

NAME=""; MARKET=""; CODE=""; DEST=""; INCLUDE=""; ALLOW_ALL=0
SID="lixinger-ipo-$(date +%s)"

VENV="${LIXINGER_VENV:-$HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl}"
CLI="$VENV/bin/qqbrowser-skill"
BASE="https://www.lixinger.com/analytics/company/detail"
DOWNLOADS="${LIXINGER_DOWNLOADS:-$HOME/Downloads}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --market) MARKET="$2"; shift 2;;
    --code) CODE="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --include) INCLUDE="$2"; shift 2;;    # 逗号分隔的关键词, 标题命中任一才下载
    --all) ALLOW_ALL=1; shift;;           # 显式全量（不推荐, 仅特殊场景）
    -h|--help) awk 'NR>2 && /^# =/{exit} NR>2{sub(/^# ?/,""); print}' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

if [ -z "$NAME" ] || [ -z "$MARKET" ] || [ -z "$CODE" ] || [ -z "$DEST" ]; then
  echo "❌ 缺少必填参数。用法: $0 --name 公司名 --market sh --code 600900 --dest 目标目录 --include 招股说明书,招股意向书"
  exit 1
fi

if [ -z "$INCLUDE" ] && [ "$ALLOW_ALL" -eq 0 ]; then
  echo "=========================================="
  echo " ❌ 已拒绝执行：未指定要下载的类型"
  echo "=========================================="
  echo " 招股资料的取舍由老板人工筛选，脚本【不得】把 IPO 分类整批灌进去。"
  echo ""
  echo " 请指定要抓的类型："
  echo "   --include 招股说明书,招股意向书"
  echo "   --include 招股意向书,摘要,附录"
  echo ""
  echo " 确实需要全量（极不推荐，会塞进大量程序性公告）："
  echo "   --all"
  exit 1
fi
if [ ! -x "$CLI" ]; then
  echo "❌ 未找到 CLI: $CLI → 先运行 scripts/setup_env.sh --install"
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then IS_MAC=1; else IS_MAC=0; fi

# 下载落地垃圾治理库（未确认*.crdownload 的隔离与同内容清理）
# shellcheck source=lib_orphans.sh
source "$(cd "$(dirname "$0")" && pwd)/lib_orphans.sh"
# PDF 完整性校验库（头部 / 体积 / 尾部）
# shellcheck source=lib_pdf.sh
source "$(cd "$(dirname "$0")" && pwd)/lib_pdf.sh"
PREFIX="${BASE}/${MARKET}/${CODE}/${CODE}"
COMPANY_DIR="$DEST/$NAME"
IPO_DIR="$COMPANY_DIR/招股资料"
mkdir -p "$COMPANY_DIR" "$IPO_DIR"

# ---------- 空壳校验（同 download_company.sh 的机制）----------
MIN_PDF_BYTES="${MIN_PDF_BYTES:-10240}"   # 招股文件有的仅几十 KB, 阈值放到 10KB
# 实现统一在 lib_pdf.sh（全 skill 一份），这里只做薄封装，避免两处走样
fsize()     { pdf_fsize "$1"; }
md5_p()     { pdf_md5 "$1"; }
valid_pdf() { pdf_acceptable "$1" "$MIN_PDF_BYTES"; }
archive() {
  local src="$DOWNLOADS/$1"; local dst="$2"
  [ -f "$src" ] || return 1
  if ! valid_pdf "$src"; then
    echo "    ❌ 空壳/半截已丢弃: $(basename "$src") $(fsize "$src")B"
    rm -f "$src"; return 1
  fi
  if [ "$IS_MAC" = "1" ]; then cp -X "$src" "$dst" 2>/dev/null || cp "$src" "$dst"; else cp "$src" "$dst"; fi
  if valid_pdf "$dst"; then rm -f "$src"; return 0; fi
  return 1
}

# ---------- 自动登录（同 download_company.sh）----------
login_if_needed() {
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_ipo_login.txt 2>&1
  if ! grep -q "登录/注册" /tmp/.lx_ipo_login.txt; then echo "  ✅ 理杏仁已登录"; return 0; fi
  echo "  🔑 未登录 → 点击右上角「登录/注册」(浏览器已存账号密码)"
  "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "登录/注册" --action click >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 4 >/dev/null 2>&1
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_ipo_login2.txt 2>&1
  if grep -qE "\[[0-9]+_[a-z0-9_]+\]<button 登录" /tmp/.lx_ipo_login2.txt; then
    "$CLI" browser_find_and_act --sessionId "$SID" --by text --value "登录" --action click >/dev/null 2>&1
    "$CLI" browser_wait --sessionId "$SID" --seconds 5 >/dev/null 2>&1
  fi
  "$CLI" browser_snapshot --sessionId "$SID" > /tmp/.lx_ipo_login3.txt 2>&1
  if grep -q "登录/注册" /tmp/.lx_ipo_login3.txt; then
    echo "  ⚠️ 自动登录未生效 → 请手动登录一次后重跑"; return 1
  fi
  echo "  ✅ 自动登录成功"; return 0
}

OK_COUNT=0; SKIP_COUNT=0; FILTERED_COUNT=0; FAIL_LIST=""; DUP_CONTENT=""; SUSPECT_LIST=""

echo "=========================================="
echo " 理杏仁招股/发行文件: $NAME ($MARKET$CODE)"
echo " 输出目录: $IPO_DIR"
echo "=========================================="

cleanup() { "$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1; }

# 开跑前先治理历史遗留: 先把「与数据集里任一在库文件逐字节相同」的孤儿删掉,
# 再把剩下的一律隔离出他的下载目录（老板 2026-09-20: 要的是"别再脏我 Downloads"）。
# 范围取 $DEST（数据集组目录），跨公司比对 —— 很多孤儿其实是别家已入库文件的副本。
pre_clean_orphans() {
  delete_twin_orphans_under "$DEST"
  relocate_orphans
  return 0
}
trap cleanup EXIT INT TERM

echo "── 开跑前治理下载目录 ──"
pre_clean_orphans

IPO_URL="${PREFIX}/announcement?announcement-type=ipo"
HITS="/tmp/.lx_ipo_hits.txt"

# ---------- 就绪判定（关键修复 2026-09-19）----------
# 教训: 公告列表是【异步渲染】的。旧版固定等 5s+3s 就采集, 页面往往还没出条目,
#   JS 计数 = 0 → 脚本误报「IPO 分类下未匹配到文件」, 让人以为数据源没有文件。
#   实测中国核电 sh601985: 需等待 ~15s 才渲染出 15 条; 2s 级轮询会全部落空。
# 现改为: 轮询 JS 里的 pdf 链接数(锚点 href 真实可数, 与视口无关),
#   连续两次一致才算就绪; 首轮为 0 则重新导航再采一轮(排除「页面没加载」的假 0)。
pdf_count_js() {
  "$CLI" browser_eval_content_js --sessionId "$SID" \
    --script "(()=>'PDFCNT='+[...document.querySelectorAll('a')].filter(x=>/\.pdf/i.test(x.getAttribute('href')||'')).length)()" 2>/dev/null \
    | grep -oE 'PDFCNT=[0-9]+' | head -1 | cut -d= -f2
}
EXPECT=""   # JS 给出的权威条目数, 供 collect_hits 提前收敛
wait_ready() {
  local i cur prev="" stable=0 waited=0
  for i in $(seq 1 12); do
    cur=$(pdf_count_js)
    if [ -n "$cur" ] && [ "$cur" -gt 0 ] 2>/dev/null; then
      if [ "$cur" = "$prev" ]; then stable=$((stable+1)); else stable=0; fi
      prev="$cur"
      if [ "$stable" -ge 1 ]; then
        EXPECT="$cur"
        echo "  ⏱️  列表就绪(等待约 ${waited}s, 页面 pdf 链接 ${cur} 个)"
        return 0
      fi
    fi
    "$CLI" browser_wait --sessionId "$SID" --seconds 3 >/dev/null 2>&1
    waited=$((waited+3))
  done
  EXPECT=""
  echo "  ⏱️  等待 ${waited}s 仍未确认 pdf 链接(可能确为 0 条)"
  return 1
}
collect_hits() {
  # snapshot 只捕获视口内元素 → 分段滚动逐屏采集
  # 提前收敛: 收齐 EXPECT 条即停(招股列表通常仅 2~22 条, 不必每次滚满 19 屏)
  "$CLI" browser_scroll_to_bottom --sessionId "$SID" >/dev/null 2>&1   # 先触发懒加载
  "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
  : > /tmp/.lx_ipo.txt
  local pos got
  for pos in 0 400 800 1200 1600 2000 2400 2800 3200 3600 4000 4500 5000 6000 7000 8000 9000 10500 12000; do
    "$CLI" browser_eval_content_js --sessionId "$SID" \
      --script "window.scrollTo(0,${pos});'ok'" >/dev/null 2>&1
    "$CLI" browser_wait --sessionId "$SID" --seconds 1 >/dev/null 2>&1
    "$CLI" browser_snapshot --sessionId "$SID" >> /tmp/.lx_ipo.txt 2>&1
    got=$(grep -oE "\[[0-9]+_[a-z0-9_]+\]<a [^/>]*/>points to a pdf" /tmp/.lx_ipo.txt | sort -u | wc -l | tr -d ' ')
    if [ -n "$EXPECT" ] && [ "$EXPECT" -gt 0 ] 2>/dev/null && [ "$got" -ge "$EXPECT" ]; then break; fi
  done
  # 提取所有指向 pdf 的条目(不限标题, IPO 分类下全是发行文件)
  grep -oE "\[[0-9]+_[a-z0-9_]+\]<a [^/>]*/>points to a pdf" /tmp/.lx_ipo.txt | sort -u > "$HITS"
}

"$CLI" browser_start_session --sessionId "$SID" --title "$NAME招股" --color green \
  --initialUrl "$IPO_URL" >/dev/null 2>&1
trap cleanup EXIT INT TERM
echo "✅ 会话已开启"
login_if_needed || true

echo "── 采集发行文件清单 ──"
wait_ready || true
collect_hits
COUNT=$(wc -l < "$HITS" | tr -d ' ')

# 兜底重试: 首轮 0 条时重新导航再采一轮, 把「页面未加载」和「真的 0 条」区分开
if [ "$COUNT" -eq 0 ]; then
  echo "  🔄 首轮采集为 0, 重新加载页面后重试一次…"
  "$CLI" browser_go_to_url --sessionId "$SID" --url "$IPO_URL" >/dev/null 2>&1
  wait_ready || true
  collect_hits
  COUNT=$(wc -l < "$HITS" | tr -d ' ')
fi
echo "── 发现 $COUNT 个发行文件 ──"

# ---------- 重名标题检测（关键修复 2026-09-19）----------
# 教训: 同一公司的两份【不同】公告可能标题完全一样 —— 实测:
#   三峡能源「…首次公开发行部分限售股上市流通公告」2024-06-05 与 2023-03-20 各一份;
#   中国广核「华泰联合…向不特定对象发行A股可转换公司债券…发行保荐书」3 份。
#   标题一样、PDF 不同。旧版按「标题」命名 → 后一份直接覆盖前一份 → 静默丢文件。
# 对策: 预先找出重名标题, 这类条目按【出现次序】编号:
#   第 1 次 → {公司}_{标题}.pdf, 第 2 次 → {公司}_{标题}(2).pdf, 依此类推。
#   ⚠️ 早先版本用「从下载临时名提取公告日期」做后缀, 在上交所(600905_20240605_4QY7.pdf)
#      可行, 但在深交所得不到可用名(实测落到「未确认 986022.crdownload」) → 日期后缀失效,
#      3 条重名仍互相覆盖。序号方案与交易所命名格式无关, 且次序确定 → 幂等成立。
DUP_TITLES="/tmp/.lx_ipo_dup_titles.txt"
DUPSEQ="/tmp/.lx_ipo_dupseq.txt"
sed -E 's/^\[[0-9]+_[a-z0-9_]+\]<a //; s#/>points to a pdf$##' "$HITS" | sort | uniq -d > "$DUP_TITLES"
: > "$DUPSEQ"
DUPN=$(wc -l < "$DUP_TITLES" | tr -d ' ')
[ "$DUPN" -gt 0 ] && echo "  ⚠️  $DUPN 组重名标题(不同公告同名) → 按出现次序加 (2)(3) 后缀, 避免互相覆盖"

# ---------- 下载目录快照（同时纳入 .crdownload）----------
# 教训(2026-09-19 实测): 部分交易所(如深交所 static.szse.cn)的 PDF 下载完成后
#   浏览器【不会改名】, 而是留成「未确认 NNNNNN.crdownload」。实测 73 个此类文件
#   全部是完整 PDF(头 %PDF- + 尾 %%EOF), 内容好端端的, 只是名字没落定。
#   旧版只 grep "\.pdf$" → ① 这些文件被当成「未检测到下载」而漏抓(数据丢失),
#   ② 文件永远留在用户下载目录里堆积(实测 266MB 垃圾)。
# 对策: 快照纳入 .crdownload; 判为「有效下载结果」的条件是
#   ① *.pdf(浏览器已落定), 或
#   ② *.crdownload 且【体积已停止增长】+ 头为 %PDF-（下载中会持续变大, 停止即完成）。
#   ⚠️ 不用 %%EOF 判定完整性 —— 实测本数据集 209 份正常 PDF 里有 22 份根本没有 %%EOF,
#      拿它当硬门槛会把这 22 份误判成「没下完」。
snap_dl() {
  # ⚠️ 不要用 `stat -f '%z %N'`: BSD(macOS) 的 -f 是「文件系统模式」,
  #    实测输出的是 Inodes/Free 之类的文件系统信息(每个文件好几行垃圾), 完全不是文件名。
  #    用已在本脚本验证过的 fsize(stat -f%z / stat -c%s) 逐文件取, 稳。
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
new_lines() { comm -13 "$1" "$2" 2>/dev/null; }               # 相对上一快照的新增行(体积+名)
new_pdf()   { new_lines "$1" "$2" | grep -iE '\.pdf$' | head -1 | sed -E 's/^[0-9]+ //'; }
new_cr()    { new_lines "$1" "$2" | grep -iE '\.crdownload$' | sort -k1,1n | tail -1; }
# md5_p / fsize / valid_pdf 见上方「空壳校验」段（统一封装到 lib_pdf.sh）
# 下载落地垃圾治理（清理同内容孤儿 / 隔离剩余孤儿）统一在 scripts/lib_orphans.sh：
#   delete_twin_orphans <参照文件...>  — 与已入库文件逐字节相同的孤儿直接删（零信息损失）
#   relocate_orphans                   — 其余「未确认*.crdownload」移动到专用暂存目录，不留在他下载目录
# 重名组内容自检: 同名条目靠 --index 下载时【可能拿回同一份】(实测中国广核 3 条里 2 条字节相同,
#   而源站三份内容各异) → 这属于静默错内容, 必须报出来而不是装作成功。
# 先用体积预筛(快), 只有同体积才做 md5。
check_dup_content() {  # $1=刚归档的文件全路径; 返回 0=内容与组内他件重复
  local newf="$1" sz x
  sz=$(fsize "$newf"); [ -n "$sz" ] || return 1
  for x in "$IPO_DIR"/*.pdf; do
    [ -f "$x" ] || continue
    [ "$x" = "$newf" ] && continue
    [ "$(fsize "$x")" = "$sz" ] || continue
    if [ "$(md5_p "$x")" = "$(md5_p "$newf")" ]; then
      echo "  ⚠️  内容重复: 与「$(basename "$x")」字节相同 → 该条可能映射错(源站该为另一份), 请复核"
      return 0
    fi
  done
  return 1
}

# 触发一次下载并等它落定; 成功则 DL_NEW=文件名 并返回 0
# 判定「落定」: ① 出现 *.pdf, 或 ② *.crdownload 体积不再增长(下载中会持续变大) 且头为 %PDF-
try_download() {
  local idx="$1" i cr cand prev_cr=""
  DL_NEW=""
  snap_dl > /tmp/.lx_ipo_before.txt
  "$CLI" browser_download_file --sessionId "$SID" --index "$idx" >/dev/null 2>&1
  for i in $(seq 1 25); do          # 最多 50s(.crdownload 定型 + 大文件都要时间)
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    snap_dl > /tmp/.lx_ipo_after.txt
    DL_NEW=$(new_pdf /tmp/.lx_ipo_before.txt /tmp/.lx_ipo_after.txt)
    [ -n "$DL_NEW" ] && return 0
    cr=$(new_cr /tmp/.lx_ipo_before.txt /tmp/.lx_ipo_after.txt)
    if [ -n "$cr" ]; then
      cand=$(printf '%s' "$cr" | sed -E 's/^[0-9]+ //')
      # 接受该 .crdownload 的条件（满足其一即可）：
      #   ① 体积与上一轮一致（已停止增长）  ② 末尾已有 %%EOF/startxref（说明已写完）
      #   两个前提都要求文件头是 %PDF- —— 挡住 HTML 错误页伪装（实测 3872B 空壳）
      if pdf_head_ok "$DOWNLOADS/$cand"; then
        if [ "$cr" = "$prev_cr" ] || pdf_tail_ok "$DOWNLOADS/$cand"; then
          DL_NEW="$cand"; return 0
        fi
      fi
    fi
    prev_cr="$cr"
    [ "$i" -eq 8 ] && [ -z "$cr" ] && return 1   # 前 16s 毫无动静 → 下载未触发, 早退去重试
  done
  return 1
}

if [ "$COUNT" -eq 0 ]; then
  echo "  ⚠️ IPO 分类下确无文件(重试后仍为 0)"
  echo "     纯港股公司(华润电力/中国电力)IPO 分类为 0 条, 属数据源缺失, 非故障"
else
while IFS= read -r line; do
  [ -z "$line" ] && continue
  IDX=$(echo "$line" | grep -oE '^\[[0-9]+_[a-z0-9_]+\]' | tr -d '[]')
  # 从 "…]<a 标题/>points to a pdf" 中提取标题
  TITLE=$(echo "$line" | sed -E 's/^\[[0-9]+_[a-z0-9_]+\]<a //; s#/>.*$##')
  [ -z "$IDX" ] && continue
  # 去掉公司名前缀 → 命名更简洁
  case "$TITLE" in
    "$NAME"*) BASE_TITLE="${TITLE#"$NAME"}";;
    *)        BASE_TITLE="$TITLE";;
  esac
  BASE_TITLE=$(printf '%s' "$BASE_TITLE" | sed 's/^[_ ：:.-]*//')
  [ -z "$BASE_TITLE" ] && BASE_TITLE="$TITLE"
  # 清洗非法文件名字符
  SAFE=$(printf '%s' "$BASE_TITLE" | sed 's#[/\\:*?"<>|]#_#g' | tr -s ' ')
  DST="$IPO_DIR/${NAME}_${SAFE}.pdf"

  # ---- 类型过滤（老板铁律：不是他要的类型就跳过，绝不下载）----
  if [ "$ALLOW_ALL" -eq 0 ]; then
    _hit=0
    while IFS= read -r _kw; do
      [ -z "$_kw" ] && continue
      case "$TITLE" in *"$_kw"*) _hit=1; break;; esac
    done <<< "$(printf '%s' "$INCLUDE" | tr ',' '\n')"
    if [ "$_hit" -eq 0 ]; then
      FILTERED_COUNT=$((FILTERED_COUNT+1))
      continue
    fi
  fi

  # 重名组: 按出现次序取编号(1=无后缀, 2+=(k)) —— 次序确定, 故每条都能独立幂等
  IS_DUP=0; SEQ=1
  if [ -s "$DUP_TITLES" ] && grep -qxF "$TITLE" "$DUP_TITLES"; then
    IS_DUP=1
    SEQ=$(awk -v t="$TITLE" '$0==t{c++} END{print c+0}' "$DUPSEQ")
    SEQ=$((SEQ+1))
    printf '%s\n' "$TITLE" >> "$DUPSEQ"
    [ "$SEQ" -gt 1 ] && DST="$IPO_DIR/${NAME}_${SAFE}(${SEQ}).pdf"
  fi

  # 幂等: 已存在且校验通过 → 跳过
  if valid_pdf "$DST"; then
    echo "  ⏭️  ${SAFE}$([ "$SEQ" -gt 1 ] && echo "(${SEQ})") 已存在, 跳过"
    SKIP_COUNT=$((SKIP_COUNT+1))
    # 重名组即便跳过了也要做一次内容自检(否则历史遗留的重复内容永远不会被报出)
    if [ "$IS_DUP" -eq 1 ] && check_dup_content "$DST"; then
      DUP_CONTENT="$DUP_CONTENT ${SAFE}#${SEQ}"
    fi
    continue
  fi
  [ -f "$DST" ] && rm -f "$DST"   # 清掉空壳

  # 实测(2026-09-19): 每个会话的【第一条】下载经常不触发(浏览器需热身),
  #   表现为「未检测到下载」且连 .crdownload 都没有。故失败必须自动重试。
  NEW=""; ATTEMPT=0
  while [ "$ATTEMPT" -lt 3 ]; do
    ATTEMPT=$((ATTEMPT+1))
    if try_download "$IDX"; then NEW="$DL_NEW"; break; fi
    if [ "$ATTEMPT" -lt 3 ]; then
      echo "  🔁 未触发下载, 重试(${ATTEMPT}/3)…"
      "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    fi
  done
  if [ -n "$NEW" ]; then
    if archive "$NEW" "$DST"; then
      if [ "$IS_DUP" -eq 1 ]; then echo "  ✅ ${SAFE}(重名#${SEQ})"; else echo "  ✅ ${SAFE}"; fi
      OK_COUNT=$((OK_COUNT+1))
      delete_twin_orphans "$DST"
      # 入库后复查尾部完整性: 缺 %%EOF/startxref → 疑似截断。
      # 只告警不拒收 —— 拒收会导致反复重下(正是老板不想要的), 报告出来让人复核即可。
      if ! pdf_tail_ok "$DST"; then
        echo "  ⚠️  尾部无 %%EOF/startxref, 疑似截断(已入库, 请复核): ${SAFE}"
        SUSPECT_LIST="$SUSPECT_LIST ${SAFE}"
      fi
      if [ "$IS_DUP" -eq 1 ] && check_dup_content "$DST"; then
        DUP_CONTENT="$DUP_CONTENT ${SAFE}#${SEQ}"
      fi
    else
      echo "  ❌ 归档失败: ${SAFE}"; FAIL_LIST="$FAIL_LIST ${SAFE}"
    fi
  else
    if [ -n "$(new_cr /tmp/.lx_ipo_before.txt /tmp/.lx_ipo_after.txt)" ]; then
      echo "  ⚠️  下载未完成(.crdownload 仍在增长/非 PDF): ${SAFE}"; FAIL_LIST="$FAIL_LIST ${SAFE} [crdownload未定型]"
    else
      echo "  ⚠️  未检测到下载: ${SAFE}"; FAIL_LIST="$FAIL_LIST ${SAFE} [未落盘]"
    fi
  fi
done < "$HITS"
fi

cleanup

# 清理 ._ 垃圾
python3 - "$COMPANY_DIR" <<'PY' 2>/dev/null
import os, sys
n = 0
for root, dirs, files in os.walk(sys.argv[1]):
    for nm in list(files) + list(dirs):
        if nm.startswith('._'):
            try: os.remove(os.path.join(root, nm)); n += 1
            except Exception: pass
if n: print(f'  🧹 清理 ._ 垃圾文件 {n} 个')
PY

echo "=========================================="
echo " 完成: $NAME 招股资料"
echo " 成功 $OK_COUNT 个文件"
[ "$SKIP_COUNT" -gt 0 ] && echo " ⏭️跳过(已存在且有效) $SKIP_COUNT 个"
[ "$FILTERED_COUNT" -gt 0 ] && echo " 🚫按类型过滤(不下载, 非老板要的类型) $FILTERED_COUNT 个"
[ -n "$FAIL_LIST" ] && echo " ❌失败项:$FAIL_LIST"
[ -n "$DUP_CONTENT" ] && echo " ⚠️ 重名组内容重复(疑似映射错, 需人工复核):$DUP_CONTENT"
[ -n "$SUSPECT_LIST" ] && echo " ⚠️ 疑似截断(尾部无 %%EOF/startxref, 请复核):$SUSPECT_LIST"
# 完整性自检: 页面条目数 vs 实际处理数(成功+跳过+过滤), 不等即告警(便于发现漏抓)
DN=$(( OK_COUNT + SKIP_COUNT + FILTERED_COUNT ))
if [ "$COUNT" -gt 0 ] && [ "$DN" -lt "$COUNT" ]; then
  echo " ⚠️ 完整性告警: 页面 ${COUNT} 条 > 实际处理 ${DN} 条(差 $(( COUNT - DN )) 条), 建议重跑(幂等, 已下不再重复)"
fi
echo " 目录: $IPO_DIR"
echo "   招股资料: $(ls -1 "$IPO_DIR" 2>/dev/null | grep -c '\.pdf$') 个"
# 收尾治理(无条件执行, 包括"0 条"的日子): 确保跑完他的下载目录里没有我们产生的残留。
# 同内容的已在"归档时"逐个清过, 这里只需把剩余的一律隔离出去。
relocate_orphans
# 复查: 此刻下载目录里应当【一个我们的孤儿都没有】; 若有, 说明治理失败, 要报出来
LEFT=$(list_orphans | grep -c . || true); LEFT=${LEFT:-0}
if [ "$LEFT" -gt 0 ]; then
  echo " ⚠️ 仍有 ${LEFT} 个「未确认*.crdownload」留在下载目录(治理未生效), 请检查"
fi
if [ -d "$ORPHAN_DIR" ]; then
  echo " ℹ️  隔离暂存区: $(ls -1 "$ORPHAN_DIR" 2>/dev/null | grep -c . ) 个文件 → $ORPHAN_DIR（可直接整目录清理）"
fi
echo "=========================================="
