---
name: lixinger-download
description: 理杏仁(lixinger.com)财报批量自动下载。当用户要下载理杏仁的公司财报/Excel/CSV/年报PDF、招股说明书/招股意向书/IPO发行文件、批量抓取财务数据时使用。驱动已登录的 QQ 浏览器自动导出资产负债表、利润表、现金流量表、财务指标、营收构成、经营数据、员工数据(7类CSV,均10年) + 10年PDF年报 + IPO分类下的招股/发行文件，按「公司 / 年报PDF / 招股资料」目录结构归档。支持 A股(sh/sz)与港股(hk)通道，缺失年份可用港交所 hkexnews 直链补。无人值守，全程免费。
agent_created: true
---

# 理杏仁财报批量下载

用浏览器自动化接管**已登录理杏仁**的浏览器，按公司批量导出 7 类财报 CSV（10 年）+ 10 份年报 PDF + IPO 分类下的招股/发行文件，自动归档到规范目录。

> 本 skill 的所有流程与坑位均来自**真机实测**（macOS + QQ 浏览器；长江电力单家跑通 + 17 家电力公司批量验证）。

## 触发场景

- "下载 XX 公司的理杏仁财报"
- "批量导出理杏仁财报 Excel / CSV"
- "自动下载年报 PDF"
- "下载 XX 的招股说明书 / 招股意向书 / IPO 文件"
- 任何涉及 lixinger.com 数据导出的自动化需求

---

## 三阶段执行（**严禁跳过阶段 1、2 直接批量**）

| 阶段 | 目标 | 通过标准 |
|------|------|---------|
| **1. 环境准备** | 装依赖、起守护进程、确认登录态 | `setup_env.sh` 全绿 |
| **2. 单公司验证** | 用 1 家公司跑完整流程 | 7 CSV + 10 PDF 齐全且数据正确 |
| **3. 批量** | 按公司清单串行循环 | 每家独立子文件夹，互不影响 |

> ⚠️ 老板铁律：**先小范围验证再批量**。阶段 2 没跑通，不许进阶段 3。
> ⚠️ 阶段 3 结束后**必须盘真实落盘**（见下方「验收」），退出码 0 不代表没漏。

---

## 快速开始

### 阶段 1：环境（新电脑必做）

```bash
bash ~/.workbuddy/skills/lixinger-download/scripts/setup_env.sh
```

脚本会自检并输出缺失项。**安装细节与手动步骤见** → `references/01-environment-setup.md`

### 阶段 2：单公司验证

```bash
CLI=~/.workbuddy/binaries/python/envs/qqbrowser-ctl/bin/qqbrowser-skill
bash ~/.workbuddy/skills/lixinger-download/scripts/download_company.sh \
  --name 长江电力 --market sh --code 600900 \
  --dest "/Volumes/KIOXIA/理杏仁下载" --years 10
```

### 阶段 3：批量

**串行**驱动（浏览器守护进程是单客户端，并行会抢会话），单家 5~7 分钟，日志落文件便于事后排查。

```bash
# ✅ 推荐：直接用批量脚本（清单文件，每行「公司名|market|code」，# 开头为注释）
bash scripts/batch_download.sh --list companies.txt --dest "/Volumes/KIOXIA/理杏仁下载" --years 10

# 单家调用（补漏时用）
bash scripts/download_company.sh --name 贵州茅台 --market sh --code 600519 --dest /path --years 10
# 只补 PDF（跳过 CSV）：加 --skip-csv
```

清单文件示例（也可参考 `scripts/companies.example.json`）：
```
# 公司名|market|code
华能国际|sh|600011
龙源电力|hk|00916
```

完整驱动原理、时间预估、进度播报技巧 → `references/04-batch-playbook.md`

---

## 硬约束（必须遵守）

| 约束 | 说明 |
|------|------|
| **必须免费** | 所有工具均为开源/免费，禁止使用任何付费 API 或付费 LLM |
| **登录态** | 理杏仁账号需**手动登录一次**（脚本无法登录），cookie 持久化后即可无人值守 |
| **频率克制** | 每次导出间隔 ≥5 秒，避免触发风控/验证码 |
| **串行执行** | 多公司批量必须串行，浏览器会话不可并行 |
| **目录规范** | 见下方，禁止平铺 |
| **文件命名** | 必须带公司名前缀（理杏仁原始名如 `600900_20260430_WC8R.pdf` 完全不可读） |

### 输出目录规范

```
{目标根目录}/
├── 长江电力/
│   ├── 年报PDF/                              ← 年报 PDF 单独子层
│   │   ├── 长江电力_2016年年度报告.pdf
│   │   └── …（共 10 年）
│   ├── 招股资料/                             ← IPO/发行文件子层（老板明确要求，不可散落根目录）
│   │   ├── 长江电力_招股说明书.pdf
│   │   ├── 长江电力_招股说明书附录.pdf
│   │   └── …（走 announcement-type=ipo 下到的全套）
│   ├── 长江电力_资产负债表_合并报表_*.csv
│   ├── 长江电力_利润表_合并报表_*.csv
│   ├── 长江电力_现金流量表_合并报表_*.csv
│   ├── 长江电力_财务指标_合并报表_*.csv
│   ├── 长江电力_营收构成_*.csv
│   ├── 长江电力_经营数据_*.csv
│   └── 长江电力_员工数据_全体员工_*.csv
└── 下一家公司/
```

> ⚠️ **根目录只放 CSV**。任何 PDF（年报、招股/发行文件）都必须进对应子层，
> 否则公司目录会显得杂乱（老板 2026-09-18 明确要求）。
> 子层命名沿用老板用词：`年报PDF/`、`招股资料/`。

---

## 核心知识速查（详见 references）

**报表 URL 直达**（免点按钮，最稳）：
```
https://www.lixinger.com/analytics/company/detail/{market}/{code}/{code}/{tickerId}?fs-owner-type=consolidated&start-date={10年前}&end-date={今天}
```

| tickerId | 报表 |
|----------|------|
| `bs` | 资产负债表 |
| `ps` | 利润表 |
| `cfs` | 现金流量表 |
| `m` | 财务指标 |
| `operation-revenue-constitution` | 营收构成 |
| `operating-data` | 经营数据 |
| `employee/all-employee` | 员工数据（全体员工） |
| `announcement?search-key=年度报告` | 公告筛选页（**年报 PDF 在这里**）|
| `announcement?announcement-type=ipo` | **IPO 分类**（招股说明书/招股意向书/附录/发行公告都在这里）|

**导出三连**：点「导出CSV」→ 选「壹」→ 点「时间横排 - 降序」→ 自动下载

> ⚠️ **例外**：经营数据(`operating-data`) 弹窗**没有「壹」单位选项**（该表单位固定）。若卡在"找不到单位"直接跳过选单位、点排序即可下载。

---

## 验收：批量后必须「盘真实落盘」

⚠️ **`download_company.sh` 退出码 0 ≠ 成功**。脚本内部个别年份下载失败**不会**改变退出码，只在日志打 ⚠️/❌。
实测 12 家全部退出码 0，但真盘发现 **4 家整段 0 份 + 3 家零星缺年**。

批量结束后**必须**用 Python 盘目录（模板见 `04-batch-playbook.md` 第三节），检查每家：
CSV 数、年报 PDF 数与年份连续性、是否有 `._` 垃圾、根目录是否有散落 PDF。

> ❌ 别用 shell glob 数中文目录：`ls "$d/年报PDF"/*.pdf` 在 zsh 下对中文路径**偶发** `no matches found`，
> 会把「有文件」误判成 0 → 一律用 Python `os.listdir`。

---

## 已知限制

### 各报表页差异

- **员工数据**：该页 UI 导出按钮在自动化下不触发下载，脚本用 **DOM 提取表格 + 本地生成 CSV** 兜底（数据一致，格式为「指标 × 年份」矩阵）。
- **经营数据**：**约半数公司理杏仁未收录**（实测 17 家中 7 家没有），脚本自动跳过并在汇总里标「数据源缺失，非故障」，**不要当成 bug 去修**。详见 `03-troubleshooting.md` 第十节。

### 年报 PDF 抓取要点

- 年报链接**不在**员工页 / 经营数据页（那些页面只有临时公告），从错误页面 grep 必然 0 命中。
- 同一公司不同年份的公告标题会**混用简称与全称**（如 `中国核电2025年年度报告` vs `中国核能电力股份有限公司2021年年度报告`）。正则**不能写死公司名**，否则全称那些年份会**整年漏掉**（中国核电实测漏 2021/2022/2024）。
- `browser_snapshot` **只捕获视口内元素**，必须分段滚动 + 多次快照合并，否则漏顶部/中间的年报。
- 年报 PDF 从公告页同时受**上市时间**限制：只能拿到该公司上市之后的部分。

### 数据源上限（不是故障）

- **A 股上市晚** → 年报不足 10 年：华能水电 2017 上市（9 年）、三峡能源 2021 上市（5 年）、龙源电力 A 股 2022 上市（4 年，改走 H 股拿满）。
- **纯港股公司**（华润电力 00836、中国电力 02380）在理杏仁 IPO 分类下 **0 条**，招股文件只能另寻渠道。
- 部分老公司 IPO 分类下只有限售股流通公告、无核心招股书（浙能电力）。

### 浏览器通道

- **QQ 浏览器**通道为实测验证路径；Chrome + Playwright 为备选（见环境文档，需自行调试）。

---

## 补漏工具箱（按优先级尝试）

| 优先级 | 手段 | 适用 |
|---|---|---|
| 1 | **重跑该家 PDF 段** `download_company.sh --skip-csv` | 散缺个别年份、偶发下载失灵 |
| 2 | **港交所 hkexnews API** | 港股公司、A 股上市前年份、整段 0 份的公司 |
| 3 | 抓公告页 href + **浏览器**直下 | 单个失败年份（curl 会被防盗链拒，必须走浏览器）|
| 4 | **上交所 `queryCompanyBulletinNew.do` API 取直链 + 浏览器导航下载** | **lixinger 登录失效时**补上交所 A股 年报（详见下方「上交所直链补漏」）|
| ✗ | curl 直下交易所 PDF | `static.sse.com.cn` 有防盗链，curl 拿到的是 **3872B 空壳**；但**浏览器导航到直链可绕过**（Content-Disposition 触发下载）|
| ✗ | 巨潮 cninfo API | `new/hisAnnouncement/query` 当前返回 500，不可用 |

**完整决策树（按失败现象分支）→ `references/04-batch-playbook.md` 第四节**

### 港交所 hkexnews 补年报 · 必坑清单（2026-09 实测，17 家批量验证）

| 坑 | 现象 / 对策 |
|---|---|
| `prefix.do` 偶发空响应 | 连续请求被限流 → 重试 5~6 次；或直接**硬编码 stockId** |
| 返回是 **JSONP** | `callback({...})`，需 `t[t.find('(')+1:t.rfind(')')]` 剥壳再 `json.loads` |
| 标题繁简 + **中文数字年份** | 「年報」/「年度報告」；华电国际等用「**二零二零年年度報告**」→ 正则要支持中文数字，否则整家 0 命中 |
| 最新一年整年漏 | 2025 年报发布于 2026 年，`toDate` 需放宽到 **20261231** |
| 已知 stockId | 华润00836=6732、龙源00916=41318、中国电力02380=8048、中国神华01088=9124、华电国际01071=2430、中国广核01816=115406 |

```bash
# ① 查 stockId（偶发空响应，需重试）
curl -s "https://www1.hkexnews.hk/search/prefix.do?callback=cb&lang=ZH&type=A&name=01816&market=SEHK"
# ② 搜年报（t1code=40000 财务报表, t2code=40100 年报）
curl -s "https://www1.hkexnews.hk/search/titleSearchServlet.do?sortDir=0&sortByOptions=DateTime&category=0&market=SEHK&stockId=<ID>&documentType=-1&fromDate=20160101&toDate=20261231&title=&searchType=1&t1code=40000&t2Gcode=-2&t2code=40100&rowRange=100&lang=ZH"
# 返回 {"result":"[...]"}（需二次 json.loads），取 FILE_LINK 拼 https://www1.hkexnews.hk 前缀
```
> 港股年报为繁体中文版，命名仍统一为 `{公司名}_{YYYY}年年度报告.pdf`。

### 上交所直链补漏（lixinger 登录失效时，2026-09 实测可用）

lixinger 登录态偶发丢失（浏览器会话不持久化 cookie），此时 A股 年报无法走原流程。
改走**上交所官方 API 取直链 + 浏览器导航下载**，全程免费、无需登录：

1. **取直链**（curl 即可，关键是带 Referer，否则 403）：
```
https://query.sse.com.cn/security/stock/queryCompanyBulletinNew.do?isPagination=true
  &productId={6位代码}&securityCode={代码}&SECURITY_CODE={代码}
  &beginDate=YYYY-MM-DD&endDate=YYYY-MM-DD
  &pageHelp.pageSize=50&pageHelp.pageNo=N
```
  请求头必须带 `Referer: https://www.sse.com.cn/disclosure/listedinfo/announcement/`。
2. **解析**：返回 `result` 是「公告组」数组，每组含若干变体，变体字段 `TITLE` + `ORG_FILE_TYPE`(0=摘要,1=全文) + 相对 `URL`。
   拼 `https://static.sse.com.cn` + `URL` 即 PDF 直链。
   匹配标题含「`YYYY`年年度报告」、排除「摘要/半年度/H股」；分页拉全（按日期倒序，老年报在后面页）。
3. **下载绕过防盗链**：直链 **curl 必拿到 3872B 空壳**（static.sse.com.cn 防盗链）。
   正确做法是用 qqbrowser-skill 让**浏览器导航到直链**触发下载：
   `browser_go_to_url --sessionId <SID> --url <直链>` → 浏览器按 Content-Disposition 把 PDF 存到 `~/Downloads`。
   ⚠️ `browser_download_url` **没有 URL 参数**（定义里无 params），不可用；只能 `browser_go_to_url` 导航触发。
4. **校验**：落盘后查 `%PDF-` 头 + 大小 >1MB，再 `cp -X`（不带 xattr，避免 exFAT 生成 `._`）归档到 `年报PDF/`。

> 实测：华能国际 2023/2024、三峡能源 2025 三个此前 3872B 空壳，均用此法从 `static.sse.com.cn` 补回真实 PDF（7.0/6.7/2.5 MB）。
> **2025 年报发布于 2026**，beginDate 要放宽到 2026 才能命中（同 hkexnews 的 toDate 放宽逻辑）。

### 招股说明书 / 招股意向书 —— 必须走「IPO 分类」，别用 search-key

⚠️ **重要教训（2026-09 实测）**：用 `search-key=招股说明书` 只能命中标题里写死"招股说明书"的文件，
**会漏掉大量叫「招股意向书」的文件**（老公司尤其如此，它们 IPO 时用的是"意向书"而非"说明书"）。
正确做法是**公告页 IPO 分类**：
```
{BASE}/{market}/{code}/{code}/announcement?announcement-type=ipo
```
> 实测对比（同一批 17 家）：`search-key` 只找到 5 家；**IPO 分类 15 家有文件、共 151 份**。

IPO 分类下收录的是整套发行文件：
招股意向书/摘要/**附录**（附录常几十 M，含完整财务明细）、招股说明书/摘要、
发行公告、网上·网下发行公告、网上路演公告、投资风险特别公告、
初步询价/定价/中签率/摇号中签结果公告、上市公告书、发行保荐书、法律意见书、限售股上市流通公告；
港股页面对应「全球發售」「網上預覽資料集」。

下载要点：
- snapshot 抓每行 `[idx]<a 标题/>points to a pdf`，逐个 `browser_download_file`（上交所直链有防盗链，curl 下不动）。
- 归档到 `{公司}/招股资料/`，命名 `{公司名}_{标题去掉公司名前缀}.pdf`；已存在且 >10KB 就跳过。
- 条目数差异大（2~30 条/家）：中国广核 30、华能水电 25、三峡能源 22、中国西电 18、中国核电 15。

---

## 写脚本必避的坑

### shell 陷阱（本机实测：macOS + WorkBuddy Bash 工具**按 zsh 语义**执行）

| 陷阱 | 错在哪 | 正确写法 |
|---|---|---|
| `declare -A` 关联数组 | 报 `syntax error: operand expected` | 用并行索引数组（`names=(...)` / `codes=(...)`）|
| `read -ra arr` | zsh 不认 `-ra` | 整串传给 Python 用 `split(',')`，或用 `cut -d'\|' -f1` |
| `echo "$res" \| python3 <<'PY'` | heredoc 覆盖 stdin，Python 读不到管道 JSON | 先 `curl ... > /tmp/x.json`，Python 从**文件**读 |
| `python3 /tmp/x.json` | 把 JSON 当 Python 脚本执行（报 `false is not defined`）| `python3 - /tmp/x.json "$arg" <<'PY'`，`-` 从 heredoc 读代码，路径走 argv |
| 中文目录 glob | zsh 下 `ls "$d/年报PDF"/*.pdf` 偶发 `no matches found` | 用 Python `os.listdir` |

### 外置盘 `._` 垃圾

exFAT 外置盘（如 KIOXIA）每次新建/移动文件都会生成 `._` AppleDouble 垃圾：
- 正则 `(YYYY)年年度报告` **会把它算成一份 PDF** → 盘点/去重先排除 `._` 前缀。
- 收尾用 Python 遍历删（清理模板见 `04-batch-playbook.md` 第八节）。

### 后台长任务

WorkBuddy 后台 Bash 任务**跨会话会 `not found`**（隔夜后丢失）。
关键补丁要么前台跑（timeout 放长），要么跑完**立即核验落盘**——记录丢了但文件通常已写入。

---

## 参考文件

| 文件 | 何时读 |
|------|--------|
| `references/01-environment-setup.md` | **新电脑/新环境必读**——安装步骤、依赖版本、登录态准备 |
| `references/02-lixinger-internals.md` | 写脚本或流程出错时——URL 模式、导出机制、各页面差异、完整命令 |
| `references/03-troubleshooting.md` | 报错/下载失败时——坑位清单与排查决策树 |
| `references/04-batch-playbook.md` | **多公司批量时必读**——驱动脚本模板、验收盘点、**补漏决策树**、17 家实测结果表 |
| `scripts/setup_env.sh` | 环境自检与一键安装 |
| `scripts/download_company.sh` | 单公司完整下载主脚本（参数化，支持 `--skip-csv` / `--skip-pdf`）|
| `scripts/batch_download.sh` | **批量串行驱动**（读清单文件，逐家调用主脚本，日志 + 即时播报失败项）|
| `scripts/companies.example.json` | 批量公司清单模板 |
