#!/usr/bin/env python3
# verify_csv_units.py - 理杏仁 CSV 单位 / 报告期核验
# 用途: 防止 skill 静默导出「亿」单位(表头写"货币:元"会骗人) 或 混入中报/季报。
# 用法:
#   python3 verify_csv_units.py <文件或目录> [...]      # 支持多路径 / 目录(递归找 .csv)
#   python3 verify_csv_units.py /path/to/理杏仁财报/
# 退出码: 0=无硬问题, 1=存在问题(读取失败/空文件/单位疑似亿/含非年报列), 2=无输入
import sys, os, csv, re

ANCHORS = ['资产总计', '营业总收入', '营业收入', '负债合计',
           '经营活动产生的现金流量净额', '归属于上市公司股东的净利润']
# 行名归一化: 去 BOM/空格/前导序号(一、/（一）/1./①)/尾部单位括号, 用于「精确」匹配锚点。
# 必须精确: 子串匹配会让「人均营业总收入」「每股经营活动产生的现金流量净额」等派生指标误当大数锚点。
SEQ_RE = re.compile(r'^(?:[一二三四五六七八九十]+[、.]|[（(][一二三四五六七八九十\d]+[)）]|\d+[、.．]|[①-⑳])\s*')
UNIT_SUFFIX_RE = re.compile(r'[（(]\s*(?:亿元|万元|元|亿)\s*[)）]\s*$')
# 收紧: 只认合法日期(19xx/20xx 年, 月 01-12, 日 01-31), 避免把 CSV 文本里的 "2507-07-85" 误判成报告期
DATE_RE = re.compile(r'((?:19|20)\d{2})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])')
YM_RE = re.compile(r'((?:19|20)\d{2})\s*年')
# 纯年份单元格(员工数据/营收构成表头写作「2025」): 属年末快照, 按年报口径处理
YEAR_ONLY_RE = re.compile(r'^\s*((?:19|20)\d{2})\s*$')

def norm_name(s):
    s = str(s).replace('\ufeff', '').replace(' ', '').replace('\u3000', '').strip()
    s = SEQ_RE.sub('', s)
    s = UNIT_SUFFIX_RE.sub('', s)
    return s

def find_anchor(rows):
    for r in rows:
        if not r:
            continue
        name = norm_name(r[0]) if r[0] else ''
        if name in ANCHORS:
            return r
    return None

def parse_num(v):
    if v is None:
        return None
    raw = str(v).strip()
    if '"' in raw:
        # ="600436" / ="片仔癀" 这类文本包装(股票代码/公司名列), 属标识不是数值, 不参与量级比较
        return None
    s = raw.lstrip('=').replace(',', '').replace('亿', '').strip()
    if s in ('', '-', '--', 'None', 'nan'):
        return None
    try:
        return float(s)
    except ValueError:
        m = re.search(r'-?\d+(\.\d+)?', s)
        return float(m.group()) if m else None

def check_file(path):
    issues = []
    try:
        with open(path, encoding='utf-8', errors='ignore', newline='') as f:
            rows = list(csv.reader(f))
    except Exception as e:
        return [f'读取失败: {e}']
    if not rows:
        return ['空文件']

    # 报告期行: 找含最多合法日期/年份标记的列首行
    header_idx, best = -1, 0
    for i, r in enumerate(rows):
        cnt = sum(1 for c in r[1:] if DATE_RE.search(str(c)) or YM_RE.search(str(c)))
        if cnt > best:
            best, header_idx = cnt, i
    periods = []
    if header_idx >= 0:
        for c in rows[header_idx][1:]:
            t = str(c)
            m = DATE_RE.search(t)
            if m:
                periods.append(f'{m.group(1)}-{m.group(2)}-{m.group(3)}')
                continue
            ym = YM_RE.search(t)
            if ym:
                periods.append(ym.group(1) + '-12-31')   # 「2024年」→ 年报口径
                continue
            yo = YEAR_ONLY_RE.match(t)
            if yo:
                periods.append(yo.group(1) + '-12-31')   # 「2024」→ 年报口径
    non_annual = [p for p in periods if not p.endswith('-12-31')]
    if periods and non_annual:
        issues.append(f'含非年报报告期 {len(non_annual)} 个(示例: {", ".join(non_annual[:4])})')

    # 锚点数值量级(元单位资产总计≈5.6e11, 亿单位≈5.6e3, 量级差1e8倍, 阈值1e6安全)
    # 取「最大绝对值」判定: 真金额远大于股票代码/公司名等标识列, 且不依赖「最新年在最右」的排序假设
    anc = find_anchor(rows)
    if anc:
        vals = [abs(v) for v in (parse_num(c) for c in anc[1:]) if v is not None]
        if vals:
            peak = max(vals)
            if 0 < peak < 1e6:
                issues.append(f'锚点[{anc[0]}]最大量级={peak:.4g} 疑似「亿」单位(元应≥1e9)')
        if re.search(r'[（(]\s*亿', str(anc[0])):
            issues.append(f'锚点行名仍含(亿)后缀: {anc[0]}')
    else:
        # 营收构成/员工数据等表可能无大数锚点 → 仅提示, 不计为硬错误
        return ['ⓘ 该表无大数锚点指标(营收构成/员工数据等)，未做单位核验']
    return issues

def main():
    if any(a in ('-h', '--help') for a in sys.argv[1:]):
        print('用法: python3 verify_csv_units.py <文件|目录> [...]')
        print('  目录会递归查找 .csv; 退出码 0=无问题 1=有问题 2=无输入')
        sys.exit(0)
    paths = []
    for a in sys.argv[1:]:
        if os.path.isdir(a):
            for root, _d, files in os.walk(a):
                for fn in sorted(files):
                    if fn.lower().endswith('.csv') and not fn.startswith('._'):
                        paths.append(os.path.join(root, fn))
        elif not os.path.basename(a).startswith('._'):
            paths.append(a)
    if not paths:
        print('用法: python3 verify_csv_units.py <文件|目录> [...]')
        sys.exit(2)
    total = bad = 0
    print(f'{"文件":<56} {"结论":<8} 问题')
    print('-' * 100)
    for p in paths:
        iss = check_file(p)
        # 硬问题: 读取失败/空文件(文件缺失或损坏绝不能静默放过) + 单位疑似亿 + 含非年报 + (亿)后缀
        unreadable = any(i.startswith('读取失败') or i == '空文件' for i in iss)
        hard = unreadable or any(('疑似' in i) or ('含非年报' in i) or ('后缀' in i) for i in iss)
        total += 1
        if hard:
            bad += 1
        if unreadable:
            verdict = '✗读失败'
        elif hard:
            verdict = '✗疑亿'
        else:
            verdict = 'ⓘ跳过' if any(i.startswith('ⓘ') for i in iss) else '✓元'
        print(f'{os.path.basename(p):<56} {verdict:<8} '
              f'{"; ".join(iss) if iss else "单位=元, 年报列OK"}')
    print('-' * 100)
    print(f'共 {total} 个文件, {bad} 个问题')
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
