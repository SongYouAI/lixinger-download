#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 · 下载落地垃圾治理库（被 download_company.sh / download_ipo.sh source）
#
# 背景（2026-09-19/20 实测）：
#   浏览器的程序化下载（CDP download_file）在部分交易所（尤其深交所 disc.static.szse.cn）
#   会留下「未确认 NNNNNN.crdownload」（英文环境为「Unconfirmed NNNNNN.crdownload」）——
#   文件内容其实完好（头 %PDF-），只是浏览器没给它落定名字，就一直赖在【用户的下载目录】里。
#   实测一次全量巡检堆到 148 个 / 461MB，把老板的 ~/Downloads 搞得很脏。
#
#   为什么不能改成 curl 直取？
#     - 上交所 static.sse.com.cn 有机器人拦截：返回 content-type: text/html +
#       `x-tengine-error: denied by bot`，正文约 3870 字节（带任何 Referer/UA 都拦）。
#     - 深交所 disc.static.szse.cn 反而能 curl 通（无防盗链）。
#     结论：A 股主流（沪市）必须走浏览器 → 垃圾无法从"生成侧"根除，只能从"落地侧"治理。
#
# 治理策略（三级，全部零信息损失）：
#   ① 同内容即删：孤儿与【已入库文件】逐字节相同 → 直接删（内容已在库里，纯冗余）
#   ② 隔离搬运：其余「未确认*.crdownload」一律【移动】到专用暂存目录，不再留在下载目录
#      （用 mv 不用 rm —— 可能是我们没拿到的那一份，留档可查）
#   ③ 暂存去重：搬运时若暂存区已有同 md5 文件，则本次这份删掉（避免暂存无限膨胀）
#
# 可调环境变量：
#   LIXINGER_ORPHAN_DIR   暂存目录（默认 ~/Library/Caches/lixinger-download/orphans）
# ============================================================

ORPHAN_DIR="${LIXINGER_ORPHAN_DIR:-$HOME/Library/Caches/lixinger-download/orphans}"
# 孤儿文件名模式：仅匹配浏览器"未命名程序化下载"，绝不碰用户自己的正常下载
ORPHAN_GLOB_ZH="未确认*.crdownload"
ORPHAN_GLOB_EN="Unconfirmed*.crdownload"

# 体积/md5 的实现统一在 lib_pdf.sh（全 skill 只此一份），这里只做薄封装。
# ⚠️ 本库必须与 lib_pdf.sh 一起 source（两个下载脚本都已这么做）。
_orph_fsize() { pdf_fsize "$1"; }
_orph_md5()   { pdf_md5 "$1"; }

# 列出下载目录里的孤儿（只认「未确认*/Unconfirmed*」模式；含空格文件名用 NUL 分隔安全遍历）
list_orphans() {
  local d="${1:-$DOWNLOADS}" f base
  for f in "$d"/$ORPHAN_GLOB_ZH "$d"/$ORPHAN_GLOB_EN; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
      未确认*|Unconfirmed*) printf '%s\n' "$f" ;;
    esac
  done
}

# ① 孤儿与给定参照文件（可多个）逐字节相同 → 删
#   用法: delete_twin_orphans <参照文件...>        # 支持通配符展开
#   实现要点: 先建「体积 → 路径」索引（只 stat，不给整个库算哈希 —— 库里有几 GB 年报，
#   全量哈希太慢），再对每个孤儿【只跟同体积的候选】做 md5。同体积才比对，快且准。
delete_twin_orphans() {
  local ref f sz h cand n=0
  local idx
  idx=$(mktemp /tmp/.lx_orphidx.XXXXXX) || return 0
  for ref in "$@"; do
    [ -f "$ref" ] || continue
    sz=$(_orph_fsize "$ref"); [ -n "$sz" ] || continue
    printf '%s\t%s\n' "$sz" "$ref" >> "$idx"
  done
  if [ ! -s "$idx" ]; then rm -f "$idx"; return 0; fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sz=$(_orph_fsize "$f"); [ -n "$sz" ] || continue
    h=""
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      [ -n "$h" ] || h=$(_orph_md5 "$f")
      if [ "$(_orph_md5 "$cand")" = "$h" ]; then
        rm -f "$f"; n=$((n+1)); break
      fi
    done < <(awk -F'\t' -v s="$sz" '$1==s{print $2}' "$idx")
  done < <(list_orphans)
  rm -f "$idx"
  [ "$n" -gt 0 ] && echo "  🧹 清理同内容残留 .crdownload ${n} 个（内容已在库中，删之无损）"
  return 0
}

# ①' 以「数据集根目录」为范围做同内容清理：<root>/*/招股资料/*.pdf 与 <root>/*/年报PDF/*.pdf
#     也兼容直接传某家公司的目录（<root>/招股资料/*.pdf）
#     用法: delete_twin_orphans_under "$DEST"
delete_twin_orphans_under() {
  local root="$1"
  [ -d "$root" ] || return 0
  local refs=()
  local f
  for f in "$root"/*/招股资料/*.pdf "$root"/*/年报PDF/*.pdf \
           "$root"/招股资料/*.pdf "$root"/年报PDF/*.pdf; do
    [ -f "$f" ] && refs+=("$f")
  done
  [ "${#refs[@]}" -eq 0 ] && return 0
  delete_twin_orphans "${refs[@]}"
  return 0
}

# ② 把剩余孤儿全部【移动】到暂存目录（+ ③ 暂存内同内容去重 + ④ 暂存过期清理）
#   暂存目录是【缓存】性质: 只放"没能归位"的残留, 便于事后追查; 超期自动清, 不会无限增长。
relocate_orphans() {
  local f base dst sz h n=0 nd=0 nold=0
  local -a seen=()
  local keep_days="${LIXINGER_ORPHAN_KEEP_DAYS:-7}"

  # ④ 暂存过期清理(按修改时间)
  if [ -d "$ORPHAN_DIR" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rm -f "$f" && nold=$((nold+1))
    done < <(find "$ORPHAN_DIR" -maxdepth 1 -type f -iname '*.crdownload' -mtime +"$keep_days" 2>/dev/null)
    [ "$nold" -gt 0 ] && echo "  🗑️  暂存区过期清理 ${nold} 个（超过 ${keep_days} 天）"
  fi

  # 先收集暂存区已有指纹，供去重
  if [ -d "$ORPHAN_DIR" ]; then
    for f in "$ORPHAN_DIR"/*.crdownload; do
      [ -f "$f" ] || continue
      seen+=("$(_orph_fsize "$f"):$(_orph_md5 "$f")")
    done
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    sz=$(_orph_fsize "$f"); h=$(_orph_md5 "$f")
    local dup=0 s
    for s in ${seen+"${seen[@]}"}; do
      if [ "$s" = "${sz}:${h}" ]; then dup=1; break; fi
    done
    if [ "$dup" -eq 1 ]; then rm -f "$f"; nd=$((nd+1)); continue; fi
    mkdir -p "$ORPHAN_DIR"
    base=$(basename "$f")
    dst="$ORPHAN_DIR/$base"
    if [ -e "$dst" ]; then
      dst="$ORPHAN_DIR/$(date +%s)_${RANDOM}_${base}"
    fi
    if mv -f "$f" "$dst" 2>/dev/null; then
      seen+=("${sz}:${h}")
      n=$((n+1))
    fi
  done < <(list_orphans)
  if [ "$n" -gt 0 ]; then
    echo "  📦 已隔离下载残留 ${n} 个 → $ORPHAN_DIR"
  fi
  [ "$nd" -gt 0 ] && echo "  🧹 暂存区同内容去重 ${nd} 个"
  return 0
}
