#!/usr/bin/env bash
# ============================================================
# 理杏仁下载 · PDF 完整性校验库（被 download_company.sh / download_ipo.sh source）
#
# 目的：把「空壳下载」挡死在入库之前，同时【绝不误拒真文件】（误拒会导致反复重下，
#       正是老板明确不想要的"重复下载"）。
#
# 三道判据（由弱到强，见 pdf_* 函数）：
#   ① pdf_head_ok   文件头 == %PDF-          —— 挡 HTML 错误页伪装成 .pdf（实测 3872B 空壳即此类）
#   ② pdf_size_ok   体积 >= 阈值             —— 挡 0 字节 / 截断到几 KB 的半成品
#   ③ pdf_tail_ok   末 4KB 含 %%EOF 或 startxref —— 挡"头部完好但尾部缺失"的截断件
#
# ⚠️ 关于 ③ 的口径（2026-09-20 实测修正，别再写错）：
#   本数据集（/Volumes/KIOXIA/上市公司研究 + 理杏仁下载）共 358 份 PDF，
#   末 4KB **100% 含 %%EOF 或 startxref** —— 0 例外（含招股资料 + 年报）。
#   ⚠️ 早先注释里写过「209 份里 22 份没有 %%EOF」，那是**测量 bug 造成的假阴性**
#      （tr 遇 PDF 非法 UTF-8 失败 + BSD grep 遇 NUL 短路，两个坑见下），真实是 0 例外。
#   注意 "0 例外" 是【本数据集实测】，不代表世界上所有 PDF 都有该标记
#   （PDF 规范允许增量更新等形态）→ 所以 ③ 只做"加分项"，绝不做"硬门槛"。
# ============================================================

# ---------- 基础原语（全 skill 只此一份实现，其余脚本/库一律薄封装调用）----------
_pdf_fsize() { if [ "${IS_MAC:-0}" = "1" ]; then stat -f%z "$1" 2>/dev/null; else stat -c%s "$1" 2>/dev/null; fi; }
_pdf_md5()   { if [ "${IS_MAC:-0}" = "1" ]; then md5 -q "$1" 2>/dev/null; else md5sum "$1" 2>/dev/null | awk '{print $1}'; fi; }
# 公开别名（供 lib_orphans.sh 与两个脚本使用）
pdf_fsize() { _pdf_fsize "$1"; }
pdf_md5()   { _pdf_md5 "$1"; }

# ① 文件头是 PDF
pdf_head_ok() {
  [ -f "$1" ] || return 1
  [ "$(head -c 5 "$1" 2>/dev/null)" = "%PDF-" ]
}

# ② 体积达标
pdf_size_ok() {
  local f="$1" min="${2:-102400}" sz
  [ -f "$f" ] || return 1
  sz=$(_pdf_fsize "$f"); [ -n "$sz" ] || return 1
  [ "$sz" -ge "$min" ]
}

# ③ 末尾含结束标记（%%EOF 或 startxref）
# ⚠️⚠️ 三个坑全实测踩过，改之前先读这里：
#
#   坑 A（BSD grep：`-a` 配 `-E` 交替模式失效）—— **必须用两个 -e, 不要用 -E 的 | 交替**。
#     实测 `tail -c 4096 f | LC_ALL=C grep -aqE '%%EOF|startxref'` 会返回"未匹配",
#     但同一窗口 `grep -abo '%%EOF'` 明明找得到（偏移 4090）。
#     原因：macOS 的 BSD grep 在 `-E` 路径下 `-a` 未生效，遇到二进制流里的 NUL 就停止搜索，
#     而 PDF 的 trailer 之前往往就是二进制流 → 好文件被误判"缺结束标记"。
#     实测对照（同一文件同一窗口）：
#       ✗ grep -aqE '%%EOF|startxref'        → 未匹配
#       ✓ grep -aq -e '%%EOF' -e 'startxref' → 匹配
#       ✓ grep -aqF -e '%%EOF' -e 'startxref'→ 匹配
#     受害者：中国电力 4 份 HK 年报（8~18MB 扫描件）。
#
#   坑 B（tr 遇非法 UTF-8 失败）：**不要**写成
#     `tail -c N "$f" | tr -d '\r\n\0 ' | grep ...` ——
#     PDF 含非法 UTF-8 字节，非 C locale 下 tr 会失败输出空 → 必然误判。
#     早期"209 份里 22 份没有 %%EOF"就是这个坑造成的假阴性（真实是 0 例外）。
#
#   坑 C（口径）：即便本数据集实测 0 例外，③ 也只当"加分项"，不做硬门槛 ——
#     PDF 规范允许增量更新等形态，硬门槛一旦误拒就会导致反复重下（老板最不想要的）。
pdf_tail_ok() {
  local f="$1" n="${2:-4096}"
  [ -f "$f" ] || return 1
  tail -c "$n" "$f" 2>/dev/null | LC_ALL=C grep -aq -e 'startxref' -e '%%EOF'
}

# 硬门槛（用于收/拒）: 头部 + 体积。**不含**尾部，避免误拒真文件。
pdf_acceptable() {
  pdf_head_ok "$1" && pdf_size_ok "$1" "${2:-102400}"
}
