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
# ============================================================
set -uo pipefail

NAME=""; MARKET=""; CODE=""; DEST=""
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
    -h|--help) awk 'NR>2 && /^# =/{exit} NR>2{sub(/^# ?/,""); print}' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

if [ -z "$NAME" ] || [ -z "$MARKET" ] || [ -z "$CODE" ] || [ -z "$DEST" ]; then
  echo "❌ 缺少必填参数。用法: $0 --name 公司名 --market sh --code 600900 --dest 目标目录"
  exit 1
fi
if [ ! -x "$CLI" ]; then
  echo "❌ 未找到 CLI: $CLI → 先运行 scripts/setup_env.sh --install"
  exit 1
fi

if [ "$(uname -s)" = "Darwin" ]; then IS_MAC=1; else IS_MAC=0; fi
SESSION_START=$(date +%s)
PREFIX="${BASE}/${MARKET}/${CODE}/${CODE}"
COMPANY_DIR="$DEST/$NAME"
IPO_DIR="$COMPANY_DIR/招股资料"
mkdir -p "$COMPANY_DIR" "$IPO_DIR"

# ---------- 空壳校验（同 download_company.sh 的机制）----------
MIN_PDF_BYTES="${MIN_PDF_BYTES:-10240}"   # 招股文件有的仅几十 KB, 阈值放到 10KB
fsize() { if [ "$IS_MAC" = "1" ]; then stat -f%z "$1" 2>/dev/null; else stat -c%s "$1" 2>/dev/null; fi; }
valid_pdf() {
  local f="$1"; local sz hdr
  [ -f "$f" ] || return 1
  sz=$(fsize "$f"); [ -n "$sz" ] || return 1
  [ "$sz" -ge "$MIN_PDF_BYTES" ] || return 1
  hdr=$(head -c 5 "$f" 2>/dev/null)
  [ "$hdr" = "%PDF-" ] || return 1
  return 0
}
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

OK_COUNT=0; SKIP_COUNT=0; FAIL_LIST=""

echo "=========================================="
echo " 理杏仁招股/发行文件: $NAME ($MARKET$CODE)"
echo " 输出目录: $IPO_DIR"
echo "=========================================="

cleanup() { "$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1; }
trap cleanup EXIT INT TERM

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
wait_ready() {
  local i cur prev="" stable=0 waited=0
  for i in $(seq 1 12); do
    cur=$(pdf_count_js)
    if [ -n "$cur" ] && [ "$cur" -gt 0 ] 2>/dev/null; then
      if [ "$cur" = "$prev" ]; then stable=$((stable+1)); else stable=0; fi
      prev="$cur"
      if [ "$stable" -ge 1 ]; then
        echo "  ⏱️  列表就绪(等待约 ${waited}s, 页面 pdf 链接 ${cur} 个)"
        return 0
      fi
    fi
    "$CLI" browser_wait --sessionId "$SID" --seconds 3 >/dev/null 2>&1
    waited=$((waited+3))
  done
  echo "  ⏱️  等待 ${waited}s 仍未确认 pdf 链接(可能确为 0 条)"
  return 1
}
collect_hits() {
  # snapshot 只捕获视口内元素 → 分段滚动逐屏采集(招股条目可达 30 条)
  "$CLI" browser_scroll_to_bottom --sessionId "$SID" >/dev/null 2>&1   # 先触发懒加载
  "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
  : > /tmp/.lx_ipo.txt
  for _pos in 0 500 1000 1500 2000 2500 3000 3500 4000 5000 6000 7000 8000 9000 10500 12000; do
    "$CLI" browser_eval_content_js --sessionId "$SID" \
      --script "window.scrollTo(0,${_pos});'ok'" >/dev/null 2>&1
    "$CLI" browser_wait --sessionId "$SID" --seconds 1 >/dev/null 2>&1
    "$CLI" browser_snapshot --sessionId "$SID" >> /tmp/.lx_ipo.txt 2>&1
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
# 教训: 同一公司的两份【不同】公告可能标题完全一样 —— 实测三峡能源:
#   「…首次公开发行部分限售股上市流通公告」2024-06-05 与 2023-03-20 各一份,
#   标题一模一样、PDF 不同。旧版按「标题」命名 → 后一份直接覆盖前一份 → 丢文件。
# 对策: 预先找出重名标题, 这类条目① 不能靠「文件名已存在」跳过(否则第二份永不被下),
#   ② 落地名追加公告日期后缀(日期从下载临时名里取, 如 600905_20240605_4QY7.pdf)。
DUP_TITLES="/tmp/.lx_ipo_dup_titles.txt"
sed -E 's/^\[[0-9]+_[a-z0-9_]+\]<a //; s#/>points to a pdf$##' "$HITS" | sort | uniq -d > "$DUP_TITLES"
DUPN=$(wc -l < "$DUP_TITLES" | tr -d ' ')
[ "$DUPN" -gt 0 ] && echo "  ⚠️  $DUPN 个重名标题(不同公告同名) → 用公告日期后缀区分, 避免互相覆盖"

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

  # 是否属于「重名标题」组: 是 → 禁用「存在即跳过」, 必须下载后用日期区分
  IS_DUP=0
  if [ -s "$DUP_TITLES" ] && grep -qxF "$TITLE" "$DUP_TITLES"; then IS_DUP=1; fi

  # 幂等: 已存在且校验通过 → 跳过（重名标题除外，否则第二份永远下不到）
  if [ "$IS_DUP" -eq 0 ] && valid_pdf "$DST"; then
    echo "  ⏭️  ${SAFE} 已存在, 跳过"
    SKIP_COUNT=$((SKIP_COUNT+1)); continue
  fi
  # 重名组: 清掉历史遗留的无后缀版本(它是本组其中一份的旧命名, 将被下面带日期的命名取代)
  if [ "$IS_DUP" -eq 1 ] && [ -f "$DST" ]; then rm -f "$DST"; fi
  [ -f "$DST" ] && rm -f "$DST"   # 清掉空壳

  ls "$DOWNLOADS" 2>/dev/null | grep -iE "\.pdf$" | sort > /tmp/.lx_ipo_before.txt
  "$CLI" browser_download_file --sessionId "$SID" --index "$IDX" >/dev/null 2>&1
  NEW=""
  for _w in 1 2 3 4 5 6 7 8 9 10; do
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    ls "$DOWNLOADS" 2>/dev/null | grep -iE "\.pdf$" | sort > /tmp/.lx_ipo_after.txt
    NEW=$(comm -13 /tmp/.lx_ipo_before.txt /tmp/.lx_ipo_after.txt | head -1)
    [ -n "$NEW" ] && break
  done
  if [ -n "$NEW" ]; then
    # 重名组: 用下载临时名里的 8 位公告日期做后缀(600905_20240605_4QY7.pdf → 20240605)
    TAG=""
    if [ "$IS_DUP" -eq 1 ]; then
      TAG=$(printf '%s' "$NEW" | grep -oE '(19|20)[0-9]{6}' | head -1)
      [ -n "$TAG" ] && DST="${DST%.pdf}_${TAG}.pdf"
    fi
    if archive "$NEW" "$DST"; then
      echo "  ✅ ${SAFE}${TAG:+ [$TAG]}"
      OK_COUNT=$((OK_COUNT+1))
    else
      echo "  ❌ 归档失败: ${SAFE}"; FAIL_LIST="$FAIL_LIST ${SAFE}"
    fi
  else
    echo "  ⚠️  未检测到下载: ${SAFE}"; FAIL_LIST="$FAIL_LIST ${SAFE}"
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
[ -n "$FAIL_LIST" ] && echo " ❌失败项:$FAIL_LIST"
# 完整性自检: 页面条目数 vs 实际处理数(成功+跳过), 不等即告警(便于发现漏抓)
DN=$(( OK_COUNT + SKIP_COUNT ))
if [ "$COUNT" -gt 0 ] && [ "$DN" -lt "$COUNT" ]; then
  echo " ⚠️ 完整性告警: 页面 ${COUNT} 条 > 实际处理 ${DN} 条(差 $(( COUNT - DN )) 条), 建议重跑(幂等, 已下不再重复)"
fi
echo " 目录: $IPO_DIR"
echo "   招股资料: $(ls -1 "$IPO_DIR" 2>/dev/null | grep -c '\.pdf$') 个"
echo "=========================================="
