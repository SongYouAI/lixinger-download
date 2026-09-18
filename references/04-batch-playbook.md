# 批量下载实战手册（多公司全流程）

> 全部来自 **2026-09 真机实测**：17 家电力公司（A 股 + 港股混合），含批量驱动、验收盘点、补漏决策树。
> 单公司流程见 SKILL.md 与 `02-lixinger-internals.md`；本文解决「**多公司批量 + 出错了怎么补**」。

---

## 一、批量前：公司清单与市场判定

先定每家的 `market` / `code`，这决定了数据上限：

| 情况 | 处理 |
|---|---|
| 普通 A 股 | `sh`/`sz` + 6 位代码 |
| 纯港股（无 A 股） | `hk` + 5 位代码（华润电力 00836、中国电力 02380） |
| **A 股上市太晚，拿不满 10 年** | **改用其 H 股页面**（龙源电力 A 股 2022 才上市 → 走 `hk/00916`，2009 上市，满 10 年） |
| 上市时间决定物理上限 | 华能水电 2017 上市（只能 9 年）、三峡能源 2021 上市（只能 5 年）→ 提前和老板确认「有多少下多少」 |

> ⚠️ 港股代码格式是 **5 位带前导零**（`00836` 不是 `836`），已实测有效。

---

## 二、批量驱动脚本模板（串行）

```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT=~/.workbuddy/skills/lixinger-download/scripts/download_company.sh
DEST="/Volumes/KIOXIA/理杏仁下载"
LOG=/tmp/lx_batch.log
: > "$LOG"
# 用普通数组，别用 declare -A（本机按 zsh 语义跑，关联数组报 syntax error）
COMPANIES=(
"华能国际|sh|600011"
"华润电力|hk|00836"
)
N=0
for c in "${COMPANIES[@]}"; do
  N=$((N+1))
  NAME=$(echo "$c" | cut -d'|' -f1)     # ⚠️ 别用 read -ra（zsh 不认）
  MKT=$(echo "$c"  | cut -d'|' -f2)
  CODE=$(echo "$c" | cut -d'|' -f3)
  echo "########## [$N/${#COMPANIES[@]}] 开始: $NAME ($MKT$CODE) $(date '+%H:%M:%S') ##########" | tee -a "$LOG"
  bash "$SCRIPT" --name "$NAME" --market "$MKT" --code "$CODE" --dest "$DEST" --years 10 >> "$LOG" 2>&1
  echo "########## [$N/${#COMPANIES[@]}] 结束: $NAME 退出码=$? ##########" | tee -a "$LOG"
done
echo "ALL_DONE" | tee -a "$LOG"
```

**要点**
- **必须串行**：浏览器守护进程是单客户端，两个会话并行会互相抢。
- 单家耗时 **5~7 分钟**（CSV ~2min + PDF 10 份轮询 ~4min）；实测 12 家约 1h17m。
- 日志落文件，事后 `grep -E "失败项|未检测|未收录|PDF:|CSV:" $LOG` 快速定位。

---

## 三、批量后必做：盘「真实落盘」（**不要信退出码**）

⚠️ **退出码 0 ≠ 成功**：脚本内部个别年份下载失败**不会**改变退出码，只在日志里打 ⚠️/❌。
实测 12 家全部退出码 0，但真盘发现 4 家整段 0 份、3 家零星缺年。

```python
import os, re
names = ["华能国际", "..."]
for n in names:
    d = os.path.join(".", n)
    csvs = [f for f in os.listdir(d) if f.endswith('.csv')]
    pd = os.path.join(d, "年报PDF")
    fs = [f for f in os.listdir(pd) if f.endswith('.pdf') and not f.startswith('._')] if os.path.isdir(pd) else []
    yrs = sorted(set(re.findall(r'(\d{4})年年度报告', f)[0] for f in fs))
    print(f"[{n}] CSV={len(csvs)} PDF={len(fs)} 年份={yrs}")
```

**两个盘点陷阱**
1. ❌ **别用 shell glob 数中文目录**：`ls "$d/年报PDF"/*.pdf` 在 zsh 下对中文路径**偶发** `no matches found`（同一循环里有的公司成功、有的失败），会把「有文件」误判成 0 → 用 Python `os.listdir`。
2. ❌ **排除 `._` 前缀**：exFAT 外置盘会生成 AppleDouble 垃圾（`._华能国际_2024年年度报告.pdf`），正则 `(YYYY)年年度报告` **会把它算成一份 PDF**，导致数量翻倍、误判重复。

---

## 四、补漏决策树（按失败模式分支）

| 现象 | 根因 | 对策（按序尝试）|
|---|---|---|
| **整段 0 份**（日志「公告页未匹配到年报链接」） | 该公司公告页在 snapshot **和** eval 下年报 `a` 标签都是 0（实测中国神华 sh601088，其他 A 股正常）| ① 重跑一次该家 ② 仍 0 → **走 H 股 hkexnews 补**（神华用 01088 补齐）|
| **整段 0 份**（港股页面） | 理杏仁 hk 页面公告筛选基本不生效 | 直接走 hkexnews（华润/龙源/中国电力都这么补的）|
| **散缺个别年份**（「未检测到下载」） | 浏览器下载偶发失灵，链接其实存在 | ① `download_company.sh --skip-csv` 重跑 PDF 段 ② 仍失败 → 抓该年 href 走浏览器直下（**curl 会被上交所防盗链拒**）|
| **缺最新一年** | 年报发布于次年，被搜索区间 `toDate` 截断 | hkexnews 的 `toDate` 放宽到**次年 1231**（2025 年报发布于 2026）|
| **年份匹配不到**（0 命中） | 繁简混用 + **中文数字年份**（华电国际「二零二零年年度報告」）| 正则支持 `年(度)?報` 且兼容中文数字 |
| **经营数据缺失** | 理杏仁**未收录**该表（实测 7/12 家没有），**数据源限制非故障** | 不补，报告中注明 |
| **上市晚导致缺年** | 物理上限（无 H 股可补） | 接受，报告说明 |

**优先顺序**：重跑（浏览器机制，最贴近已成功路径） → 港股走 hkexnews → 抓 href 浏览器直下。
**别走的路**：curl 直下上交所/深交所直链（防盗链）、巨潮 cninfo API（当前返回空）。

---

## 五、补漏脚本要点

- **A 股补 PDF 段**：`bash download_company.sh --name X --market sh --code X --dest D --years 10 --skip-csv`
  （只跑 PDF，跳过 CSV；已存在的文件会重新下载覆盖，内容一致无害）
- **H 股 / 上市前年份**：走 hkexnews（stockId 表与坑位见 SKILL.md「港交所 hkexnews 必坑清单」）
- **抓 href + curl**：仅对部分深交所链接有效（中国广核 2020 成功过），**上交所一律失败**

---

## 六、长任务工程注意（血泪）

- ⚠️ **WorkBuddy 后台 Bash 任务跨会话会 `not found`**（实测多次：隔夜后任务记录丢失）。
  - 应对：关键补丁**前台跑**（把 timeout 放长），或跑完**立即核验落盘**——任务记录丢了，但文件通常已正常写入。
- 后台跑时挂「进度观察器」实现定期播报：
  ```bash
  bash -c 'sleep 2400; grep -E "开始|结束|ALL_DONE" /tmp/lx_batch.log | tail -20'
  ```
- **每家跑完就 grep 日志的 ❌/⚠️ 行**，不要等 12 家全跑完才发现前几家全废。

---

## 七、招股 / 发行文件批量（IPO 分类）

```bash
# 路径（别用 search-key=招股说明书，会漏掉「招股意向书」）
{BASE}/{market}/{code}/{code}/announcement?announcement-type=ipo
```

下载脚本骨架：
```bash
# 1) 打开上面 URL → scroll_to_bottom → 分段 scroll（0/700/1400/2100）+ 多次 snapshot 合并
# 2) 抓每行：grep -oE "\[[0-9]+_[a-z0-9_]+\]<a [^>]*/>points to a pdf" | sort -u
# 3) 逐行取 idx + 标题 → browser_download_file → 轮询 ~/Downloads 取新 pdf → 归档
# 4) 命名 {公司名}_{标题去掉公司名前缀}.pdf，放 {公司}/招股资料/
# 5) 已存在且 >10KB 就跳过（防重复）
```
- 条目数差异极大：2~30 条/家（中国广核 30、华能水电 25、三峡能源 22）。
- 港股页面该分类：龙源 00916 有「全球發售」；华润 00836、中国电力 02380 为 0 条。

---

## 八、外置盘 `._` 垃圾巡检

```python
import os
n = 0
for root, dirs, files in os.walk("."):
    for nm in list(files) + list(dirs):
        if nm.startswith('._'):
            try:
                p = os.path.join(root, nm)
                os.remove(p) if os.path.isfile(p) else os.rmdir(p); n += 1
            except Exception:
                pass
print("清理", n, "个")
```
> 每次新建目录/移动文件都会再产生，收尾必做一次。

---

## 九、17 家电力公司实测结果（可用于预估与对账）

| 公司 | 通道 | 年报 PDF | IPO 文件 | 备注 |
|------|------|---------|---------|------|
| 华能国际 | sh600011 | 10 | 2 | 招股意向书 + 附录（IPO 分类才找到）|
| 国电电力 | sh600795 | 10 | 4 | 增发招股意向书 |
| 华电国际 | sh600027 | 10 | 2 | H 股补 2020（中文数字年份坑）|
| 大唐发电 | sh601991 | 10 | 11 | |
| 中国神华 | sh601088 | 10 | 11 | 公告页 DOM 0 链接 → H 股补 |
| 国投电力 | sh600886 | 10 | 6 | IPO 分类含 GDR 文件 |
| 华润电力 | hk00836 | 10 | 0 | 纯港股，无 IPO 文件 |
| 浙能电力 | sh600023 | 10 | 2 | 仅限售股公告 |
| 华能水电 | sh600025 | 9 | 25 | 2017 上市（上限）|
| 三峡能源 | sh600905 | 5 | 21 | 2021 上市（上限）|
| 龙源电力 | hk00916 | 11 | 2 | 走 H 股拿满 10 年 |
| 中国电力 | hk02380 | 11 | 0 | 纯港股，无 IPO 文件 |
| 长江电力 | sh600900 | 10 | 3 | |
| 国电南瑞 | sh600406 | 10 | 2 | |
| 中国核电 | sh601985 | 10 | 14 | |
| 中国西电 | sh601179 | 10 | 18 | |
| 中国广核 | sz003816 | 10 | 28 | |

**经营数据收录情况**：仅中国神华、国投电力、浙能电力、华能水电、三峡能源、长江电力 有；其余理杏仁未收录。
