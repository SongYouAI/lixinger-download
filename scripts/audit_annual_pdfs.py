#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
年报 PDF「名副其实性」全库审计
================================================================
用途：扫一个数据集根目录下所有 `*/年报PDF/*.pdf`，逐份判断"这份 PDF 真的是它
      文件名所声称的那一年年报吗"，揪出**张冠李戴**的错件。

为什么需要它（真实事故 2026-09-20）：
  理杏仁 skil 的下载脚本用 browser_download_file --index，而 index 取自
  【跨页累积快照】。翻页后索引指向当前页的任意元素 → 「下 2017 年报」实际下到
  了同期公告/评估报告/招股书，共 32 份错件。而当时只校验了 %PDF- 头 + 体积，
  全部放行入库。此脚本是事后审计 + 长期防线。

判据（与 scripts/download_company.sh 的 annual_content_ok、
      scripts/fill_via_cninfo.sh 的 content_ok 保持同步 —— 改动需三处同步）：
  ① 页数门槛  : <50 页判错（实测真年报 133~455 页，错件 1~9 页）
  ② 体裁黑名单: 前 3 页命中「招股说明书/反馈意见/独立意见/…」判错
  ③ 年份特征  : 前 30 页**去空白后**匹配「年份+年度报告/年報」（抗「2 0 2 4」字间距）
  ④ 宽松兜底  : 前 30 页同时出现年份与年报字样（港股版式差异）
  ⑤ 英文兜底  : 前 30 页含 Annual Report 且出现年份（港股英文封面）

用法:
  python3 audit_annual_pdfs.py "/path/to/01-发电运营（15家）" [--json out.json] [--quiet]
退出码: 有不合格 → 1；全部合格 → 0
"""
import os, re, sys, json, argparse

try:
    import pymupdf
except ImportError:
    try:
        import fitz as pymupdf
    except ImportError:
        print("❌ 需要 pymupdf（装: pip install pymupdf）"); sys.exit(2)

BLACK = re.compile(r'招股说明书|招股意向书|募集说明书|上市公告书|反馈意见|'
                   r'独立意见|跟踪信用评级|内部控制评价|法律意见书|评估报告书')
REPORT_WORD = re.compile(r'年度报告|年度報告|年報')
CN_MAP = {'0': '〇', '1': '一', '2': '二', '3': '三', '4': '四',
          '5': '五', '6': '六', '7': '七', '8': '八', '9': '九'}


def judge(path, year):
    """返回 (ok: bool, reason: str, npages: int)"""
    try:
        d = pymupdf.open(path)
    except Exception as e:
        return False, f"无法打开: {e}", 0
    n = len(d)
    raw30 = " ".join(d[i].get_text() for i in range(min(30, n)))
    head3 = re.sub(r'\s+', ' ', " ".join(d[i].get_text() for i in range(min(3, n))))
    d.close()
    flat = re.sub(r'[\s\u3000]', '', raw30)
    # ① 页数门槛
    if n < 50:
        return False, f"仅 {n} 页（年报通常 >100 页，此为公告类）", n
    # ② 体裁黑名单
    mb = BLACK.search(head3)
    if mb:
        return False, f"体裁不符（命中「{mb.group(0)}」）首页: {head3[:70]}", n
    # ③ 年份特征（去空格）
    cn = ''.join(CN_MAP[c] for c in year)
    pat = re.compile(rf'({year}[^0-9]{{0,4}}(年度报告|年度報告|年報))'
                     rf'|({cn}[^0-9]{{0,4}}(年度报告|年度報告|年報))')
    if pat.search(flat):
        return True, "", n
    # ④ 宽松兜底
    if year in flat and REPORT_WORD.search(flat):
        return True, "", n
    # ⑤ 英文兜底
    if re.search(r'Annual\s*Report', raw30, re.I) and year in flat:
        return True, "", n
    return False, f"{n} 页未见「{year}年度报告」字样，首页: {re.sub(r'[\s\u3000]+', ' ', raw30)[:70]}", n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", help="数据集根目录（其下每个子目录含 年报PDF/）")
    ap.add_argument("--json", default=None, help="把结果写到 JSON")
    ap.add_argument("--quiet", action="store_true", help="只打印不合格项")
    args = ap.parse_args()

    bad, total = [], 0
    per_co = {}
    for comp in sorted(os.listdir(args.root)):
        dd = os.path.join(args.root, comp, "年报PDF")
        if not os.path.isdir(dd):
            continue
        okn = 0
        for f in sorted(os.listdir(dd)):
            if f.startswith('._') or not f.lower().endswith('.pdf'):
                continue
            m = re.search(r'(\d{4})年', f)
            if not m:
                continue          # 招股资料等非年报 PDF 跳过
            total += 1
            ok, reason, n = judge(os.path.join(dd, f), m.group(1))
            if ok:
                okn += 1
            else:
                bad.append({"company": comp, "file": f, "pages": n, "reason": reason})
        per_co[comp] = okn

    if not args.quiet:
        print(f"审计根目录: {args.root}")
        print(f"年报 PDF 总数: {total}")
        print(f"合格 {total - len(bad)} / 不合格 {len(bad)}\n")
    if bad:
        print("❌ 不合格清单:")
        cur = None
        for b in bad:
            if b["company"] != cur:
                cur = b["company"]; print(f"\n  [{cur}]")
            print(f"    {b['file']}  ({b['pages']}页)  {b['reason']}")
    else:
        print("✅ 全部 PDF 名副其实")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump({"root": args.root, "total": total, "bad": bad}, fh,
                      ensure_ascii=False, indent=2)
        print(f"\n结果已写入 {args.json}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
