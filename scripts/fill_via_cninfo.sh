#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 · 巨潮(cninfo)补 A 股老年报
#
# 用途：补 2016~2023 的 A 股年报 —— 当 lixinger 公告页漏抓（标题形态异常/分页失效）
#       或上交所 API 够不到（只返回最近约 136 条）时使用。
#       亦可用于【重下内容张冠李戴的错误文件】（配 --force）。
#
# 实测（2026-09-20）：全程 curl，**不需要浏览器**，比重新翻公告页快得多。
#
# 用法:
#   bash fill_via_cninfo.sh --name 桂冠电力 --code 600236 --years 2020,2021 \
#        --dest "/path/to/17_桂冠电力/年报PDF"
#   # orgId 可省略（脚本自动查）；重下错误文件加 --force
#
# orgId 取法（沪市 gssh0600xxx / 深市 9900xxxxxx）—— 不传则自动查:
#   curl -s --noproxy '*' -X POST "http://www.cninfo.com.cn/new/information/topSearch/query" \
#     -H 'Content-Type: application/x-www-form-urlencoded' -H 'User-Agent: Mozilla/5.0' \
#     --data "keyWord=600236&maxNum=5"
#
# 产出: {dest}/{name}_{YYYY}年年度报告.pdf
#
# 🔴 双重校验（2026-09-20 加固，防"张冠李戴"）:
#   ① 体积/文件头: %PDF- 开头 且 ≥100KB
#   ② 【内容名副其实】用 pymupdf 读前 20 页，必须出现「YYYY年度报告」字样
#      （兼容 「YYYY年年度报告」「YYYY 年年度报告」「YYYY年度報告」「YYYY年報」「中文年份」）
#      —— 只查文件头会让"下成公告/评估报告"的错误文件一路绿灯入库，必须验内容。
#
# 幂等: 目标已存在且【双重校验通过】→ 跳过（--force 可强制重下）
# ============================================================
set -uo pipefail

NAME=""; CODE=""; ORG=""; YEARS=""; DEST=""
SKIP_EXIST=1
CONTENT_CHECK=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --code) CODE="$2"; shift 2;;
    --orgId) ORG="$2"; shift 2;;
    --years) YEARS="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --force) SKIP_EXIST=0; shift;;
    --no-check) CONTENT_CHECK=0; shift;;
    -h|--help) awk 'NR>3 && /^# =/{exit} NR>3{sub(/^# ?/,""); print}' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done
if [ -z "$NAME" ] || [ -z "$CODE" ] || [ -z "$YEARS" ] || [ -z "$DEST" ]; then
  echo "❌ 缺少必填参数。见 --help"; exit 1
fi
PY="${LIXINGER_PY:-/Users/niusl321/.workbuddy/binaries/python/envs/default/bin/python3}"
[ -x "$PY" ] || PY=python3
MIN_PDF_BYTES="${MIN_PDF_BYTES:-102400}"
mkdir -p "$DEST"

# ── 内容校验器 v2（页数门槛 + 体裁黑名单 + 去空格年份匹配；通过输出 OK）──
# 判据设计依据（2026-09-20 全库 196 份实测）:
#   真年报页数区间 133~455；张冠李戴的错件页数 1~9（公告）
#   → ① 页数 <50 一律判错（最有效，挡住所有薄公告）
#   → ② 前 3 页体裁黑名单挡住【厚】错件（招股书/反馈意见回复，可达数百页）
#   → ③ 前 30 页去空格后匹配「年份+年报」（应对 "2 0 2 4 年 度 報 告" 这类字间距设计）
#   → ④ 英文兜底（港股年报英文封面，如华润电力）
content_ok() {  # $1=pdf路径 $2=年份
  "$PY" - "$1" "$2" <<'PY'
import sys, re
try:
    import pymupdf
except ImportError:
    print("NO_PYMUPDF（校验器缺依赖 → 按拒收处理）"); sys.exit(1)
p, yr = sys.argv[1], sys.argv[2]
try:
    d = pymupdf.open(p)
except Exception as e:
    print(f"OPEN_ERROR {e}"); sys.exit(1)
n = len(d)
raw30 = " ".join(d[i].get_text() for i in range(min(30, n)))
head3 = re.sub(r'\s+', ' ', " ".join(d[i].get_text() for i in range(min(3, n))))
d.close()
flat = re.sub(r'[\s\u3000]', '', raw30)     # 去空白后匹配，抗「2 0 2 4」字间距设计
# ① 页数门槛
if n < 50:
    print(f"NOT_ANNUAL_REPORT 仅 {n} 页（年报通常 >100 页，此为公告类）")
    sys.exit(1)
# ② 体裁黑名单（只看前 3 页；刻意不含「承诺函/决议公告」——年报目录里会出现这些词）
BLACK = re.compile(r'招股说明书|招股意向书|募集说明书|上市公告书|反馈意见|'
                   r'独立意见|跟踪信用评级|内部控制评价|法律意见书|评估报告书')
mb = BLACK.search(head3)
if mb:
    print(f"NOT_ANNUAL_REPORT 体裁不符(命中「{mb.group(0)}」) 首页: {head3[:80]}")
    sys.exit(1)
# ③ 年份特征（去空格后匹配）
cn = ''.join({'0':'〇','1':'一','2':'二','3':'三','4':'四','5':'五','6':'六','7':'七','8':'八','9':'九'}[c] for c in yr)
pat = re.compile(rf'({yr}[^0-9]{{0,4}}(年度报告|年度報告|年報))|({cn}[^0-9]{{0,4}}(年度报告|年度報告|年報))')
if pat.search(flat):
    print("OK"); sys.exit(0)
# ④ 宽松兜底：前 30 页同时出现年份与年报字样（港股版式差异，如华电国际 2020）
if yr in flat and re.search(r'年度报告|年度報告|年報', flat):
    print("OK"); sys.exit(0)
# ⑤ 英文兜底（港股年报英文封面，如华润电力 2017）
if re.search(r'Annual\s*Report', raw30, re.I) and yr in flat:
    print("OK"); sys.exit(0)
print(f"NOT_ANNUAL_REPORT {n}页 未见「{yr}年度报告」字样 首页: {re.sub(r'\s+', ' ', raw30)[:80]}")
sys.exit(1)
PY
}

echo "=========================================="
echo " 巨潮补漏: $NAME ($CODE)"
echo " 目标年份: $YEARS"
echo " 输出目录: $DEST"
echo "=========================================="

# ── 自动查 orgId ──
if [ -z "$ORG" ]; then
  ORG=$(curl -s --noproxy '*' -X POST "http://www.cninfo.com.cn/new/information/topSearch/query" \
    -H 'Content-Type: application/x-www-form-urlencoded' -H 'User-Agent: Mozilla/5.0' \
    --data "keyWord=${CODE}&maxNum=5" \
    | "$PY" -c "import json,sys
try:
    d=json.load(sys.stdin)
    hit=[x for x in d if str(x.get('code','')).startswith('$CODE')] or d
    print(hit[0]['orgId'])
except Exception: print('')")
  [ -z "$ORG" ] && { echo "❌ 自动查 orgId 失败，请手动传 --orgId"; exit 1; }
  echo " 自动查到 orgId=$ORG"
fi

OK=0; SKIP=0; FAIL=0
for YR in ${YEARS//,/ }; do
  DST="$DEST/${NAME}_${YR}年年度报告.pdf"
  # 幂等: 已存在且【双重校验通过】→ 跳过
  if [ "$SKIP_EXIST" -eq 1 ] && [ -f "$DST" ]; then
    hd="$(head -c 5 "$DST" 2>/dev/null)"; sz=$(stat -f%z "$DST" 2>/dev/null || stat -c%s "$DST" 2>/dev/null || echo 0)
    if [ "$hd" = "%PDF-" ] && [ "$sz" -ge "$MIN_PDF_BYTES" ]; then
      if [ "$CONTENT_CHECK" -eq 1 ]; then
        if [ "$(content_ok "$DST" "$YR" || true)" = "OK" ]; then
          echo "  ⏭️  ${YR}年 已存在且双重校验通过, 跳过"; SKIP=$((SKIP+1)); continue
        fi
        echo "  🔄 ${YR}年 文件头合格但【内容不是${YR}年报】→ 强制重下"
      else
        echo "  ⏭️  ${YR}年 已存在且校验通过, 跳过"; SKIP=$((SKIP+1)); continue
      fi
    else
      echo "  🔄 ${YR}年 现有文件不合格(${sz}B) → 重下"
    fi
  fi

  # ── ① 查年报公告【候选列表】（打分排序，逐个试）──
  # 坑: pageSize 被服务端压到 30 → 必须翻页; seDate 收窄到年报披露窗口(次年 3~6 月)
  # 坑: 同一窗口里会有「关于2023年年度报告的公告 / 问询函回复」等**含年份+年度报告字样
  #     但本体是公告**的条目。旧逻辑只取第一个命中 → 下到 9~22 页的公告且"文件头合格"
  #     → 误判入库。改为：输出多个候选（干净的排前面），shell 端逐个下载+内容校验，
  #     第一个真正通过校验的才归档。
  CAND=$("$PY" - "$CODE" "$ORG" "$YR" <<'PY'
import json,sys,re,urllib.request,urllib.parse
code,org,year=sys.argv[1],sys.argv[2],int(sys.argv[3])
y2=year+1
# ⚠️ 必须绕过环境代理(本机设了 HTTP_PROXY, 否则静默失败返回空)
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
NOISE=re.compile(r'摘要|英文|English|关于|回复|问询|更正|补充|说明|公告|意见|'
                 r'监事会|董事会|股东大会|债券|评级|承诺|审计|附件|确认')
rows=[]; seen=set()
for pn in range(1,7):
    data=urllib.parse.urlencode({'stock':f'{code},{org}','tabName':'fulltext','pageSize':'30',
        'pageNum':str(pn),'seDate':f'{y2}-03-01~{y2}-06-30','isHLtitle':'true'}).encode()
    req=urllib.request.Request('http://www.cninfo.com.cn/new/hisAnnouncement/query',data=data,
        headers={'User-Agent':'Mozilla/5.0','Content-Type':'application/x-www-form-urlencoded'})
    try:
        d=json.load(opener.open(req,timeout=30))
    except Exception:
        break
    ans=d.get('announcements') or []
    if not ans: break
    for a in ans:
        t=(a.get('announcementTitle','') or '').strip()
        u=a.get('adjunctUrl','') or ''
        if not u: continue
        # 标题形态实测 3 种: "2020年度报告" / "2021 年年度报告"(带空格) / "2021年年度报告"
        if not re.search(rf'{year}\s*年?年度报告', t): continue
        if re.search(r'摘要|英文', t): continue        # 硬排除摘要/英文版
        if u in seen: continue
        seen.add(u)
        rows.append((1 if NOISE.search(t) else 0, u, t))   # 0=干净标题(年报本体), 1=疑似公告
    if len(rows) >= 8: break
rows.sort(key=lambda r: r[0])
for sc,u,t in rows[:8]:
    print(f"{sc}\t{u}\t{t}")
PY
)
  if [ -z "$CAND" ]; then echo "  ❌ ${YR}年 未在巨潮找到任何候选"; FAIL=$((FAIL+1)); continue; fi

  # ── ②③ 逐候选下载 + 双重校验（首个通过者归档）──
  DONE=0
  while IFS=$'\t' read -r _sc URL TITLE; do
    [ -z "$URL" ] && continue
    # 必须带 Referer，否则返回 1.6KB HTML 假文件
    curl -s --noproxy '*' -L -H 'User-Agent: Mozilla/5.0' -H 'Referer: http://www.cninfo.com.cn/' \
      -o /tmp/.cninfo_dl.pdf "http://static.cninfo.com.cn/${URL#/}"
    sz=$(stat -f%z /tmp/.cninfo_dl.pdf 2>/dev/null || stat -c%s /tmp/.cninfo_dl.pdf 2>/dev/null || echo 0)
    hd=$(head -c 5 /tmp/.cninfo_dl.pdf 2>/dev/null)
    if [ "$hd" = "%PDF-" ] && [ "$sz" -ge "$MIN_PDF_BYTES" ]; then
      cv="OK"
      [ "$CONTENT_CHECK" -eq 1 ] && cv="$(content_ok /tmp/.cninfo_dl.pdf "$YR" || true)"
      if [ "$cv" = "OK" ]; then
        if [ "$(uname -s)" = "Darwin" ]; then cp -X /tmp/.cninfo_dl.pdf "$DST" 2>/dev/null || cp /tmp/.cninfo_dl.pdf "$DST"
        else cp /tmp/.cninfo_dl.pdf "$DST"; fi
        echo "  ✅ ${YR}年 ($((sz/1024))KB) [候选命中] $(printf '%.58s' "$TITLE")"
        DONE=1; break
      fi
      echo "     ↩️ 候选不合格 → 换下一候选（$(printf '%.52s' "$cv")）"
    fi
    rm -f /tmp/.cninfo_dl.pdf
    sleep 1
  done <<< "$CAND"
  rm -f /tmp/.cninfo_dl.pdf
  if [ "$DONE" -eq 0 ]; then
    echo "  ❌ ${YR}年 全部候选均未通过内容校验"; FAIL=$((FAIL+1))
  else
    OK=$((OK+1))
  fi
done
echo "------------------------------------------"
echo " 成功 $OK / 跳过 $SKIP / 失败 $FAIL"
[ "$FAIL" -eq 0 ]
