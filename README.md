# 理杏仁财报批量下载

> **一句话**：告诉它公司名，它自动从 [理杏仁](https://www.lixinger.com) 把这家公司的 **7 类财报 CSV（10 年）+ 10 年 PDF 年报 + IPO 招股/发行文件** 全套下载好，按「公司 / 年报PDF / 招股资料」规范归档。**无人值守、全程免费。**

一个把「重复下载财报」这件苦力活沉淀成资产的 WorkBuddy Skill。驱动**你已登录理杏仁的 QQ 浏览器**，复用真实登录态，模拟人工完成「翻页 → 导出 → 归档」全流程。

> 本 Skill 的所有流程与坑位均来自**真机实测**（macOS + QQ 浏览器；长江电力单家跑通 + **17 家电力公司批量验证**），不是纸上方案。
>
> 🔴 **只在 macOS 上测过；Windows / Linux 从未在真机上跑过一次。** 代码里有平台适配层，但**不保证可用**。
> Windows 部署步骤见 [`references/01-environment-setup.md`](references/01-environment-setup.md) 第七节，请自行验证、风险自负。

---

## 🧭 这是什么 / 给谁用

| 项 | 说明 |
|---|---|
| **主要平台** | **WorkBuddy**（放入 `~/.workbuddy/skills/lixinger-download/` 即可被识别调用） |
| **其他 Agent** | **兼容**。`SKILL.md` 为标准 Agent Skill 格式，Claude Code / Cline 等支持 `SKILL.md` 约定的 Agent 均可加载；脚本为纯 Bash + Python。**仅 macOS 实测过**；Windows 需 Git Bash / MSYS2 / WSL（PowerShell 不支持），Linux 未测试 |
| **给谁用** | 需要**批量下载上市公司财报**做分析的价值投资者、财务研究者、投研从业者 |
| **输入** | 公司名 + 股票代码（市场段 `sh`/`sz`/`hk`） |
| **产物** | 每家公司一个文件夹：7 类 CSV（资产负债表/利润表/现金流量表/财务指标/营收构成/经营数据/员工数据，均 10 年）+ `年报PDF/` 下 10 份年报 + `招股资料/` 下 IPO 全套发行文件 |
| **成本** | **0 元**。全程用本地已登录浏览器 + 开源工具，不接任何付费 API |
| **不是** | 不是爬虫集群、不是云端服务、不绕过任何会员权限（用你自己的理杏仁账号看你能看的数据） |

---

## ✨ 每家公司的标准产出

```
{目标目录}/{公司}/
├── 年报PDF/                                  ← 年报 PDF 单独子层
│   ├── {公司}_2016年年度报告.pdf
│   └── …（共 10 年）
├── 招股资料/                                 ← IPO/发行文件单独子层
│   ├── {公司}_招股意向书.pdf
│   ├── {公司}_招股意向书附录.pdf
│   ├── {公司}_招股说明书.pdf
│   └── …（发行公告 / 保荐书 / 法律意见书 / 上市公告书等）
├── {公司}_资产负债表_合并报表.csv             ← 10 年（文件名稳定, 重跑覆盖不堆积）
├── {公司}_利润表_合并报表.csv
├── {公司}_现金流量表_合并报表.csv
├── {公司}_财务指标_合并报表.csv
├── {公司}_营收构成.csv
├── {公司}_经营数据.csv
└── {公司}_员工数据_全体员工.csv
```

**文件命名**：所有文件强制带**公司名前缀**——理杏仁原始名（如 `600900_20260430_WC8R.pdf`）完全不可读，Skill 会自动重命名。

> ⚠️ **根目录只放 CSV**。任何 PDF 都必须进 `年报PDF/` 或 `招股资料/` 子层，否则一家公司几十个文件散在根目录会非常乱。

---

## 🎯 触发场景

```
下载 XX 公司的理杏仁财报 / 批量导出理杏仁财报 Excel / 自动下载年报 PDF
把 XX 的十年财报全下载下来 / 理杏仁财报批量抓取
下载 XX 的招股说明书 / 招股意向书 / IPO 发行文件
```

**用法示例**：
> 「用 **理杏仁财报批量下载** 把长江电力（sh 600900）近十年财报下载到 `/Volumes/KIOXIA/上市公司研究/电力系统/01-发电运营（15家）`」

---

## 🔄 三阶段执行（设计上强制「先验证再批量」）

| 阶段 | 目标 | 通过标准 |
|------|------|---------|
| **1. 环境准备** | 装依赖、起守护进程、确认登录态 | `setup_env.sh` 全绿 |
| **2. 单公司验证** | 用 1 家公司跑完整流程 | 7 CSV + 10 PDF 齐全且数据正确 |
| **3. 批量** | 按公司清单循环 | 每家独立子文件夹，互不影响 |

> ⚠️ **铁律：先小范围验证再批量。** 阶段 2 没跑通，不许进阶段 3。

---

## 🚀 安装与使用

### 前置（新电脑一次性）

| 依赖 | 说明 |
|---|---|
| Python ≥ 3.9 | 运行 `qqbrowser-skill` CLI |
| `qqbrowser-skill` | 浏览器自动化 CLI（`pip install qqbrowser-skill`） |
| QQ 浏览器 | [browser.qq.com](https://browser.qq.com/) 下载；**无 Linux 版**，Linux 走 Playwright 备选通道 |
| 理杏仁账号 | **自己提供**，把账号密码交给 Agent 写入 `~/.config/lixinger-download/creds.json`（600，已 gitignore）；下载脚本开会话前自动调用 `scripts/lixinger_login.sh` 完成登录，无需人工登录 |

#### 🔑 理杏仁账号：自己提供，交给 Agent 自动登录

**本 skill 不附带任何账号密码**。最省事的做法是**把账号和密码直接发给 Agent**，让它写进
`~/.config/lixinger-download/creds.json`（权限 600、仓库外、已 gitignore）。之后
`scripts/lixinger_login.sh` 会自动填表提交，**不用你手工登录浏览器**；换号改这个文件重跑即可。

账号获取渠道：① **理杏仁官网**（官方注册 / 购买会员，稳定）；② **二手交易平台**（俗称「海鲜市场」，
即闲鱼）购买共享或租借账号，便宜但**容易过期、有账号安全与合规风险**，请自行判断承担。

> ⛔ **绝不要把真实账号密码写进 Skill 文件、提交到 Git 或贴到公开 Issue**：本仓库是公开的，
> push 出去就等于泄露。会员权限决定可见数据范围，脚本不会绕过。

#### 🔴 浏览器端三件必做（漏一项整个流程卡住）

1. **WorkBuddy 设置 → 智能体 → 浏览器操控**：打开「**让 WorkBuddy 控制浏览器**」，并装好目标浏览器的 WorkBuddy 扩展（Chrome / Edge / QQ 各一个，需显示「已安装」；无法访问扩展商店就点「**手动安装**」）。不开 → `Connected clients: 0`，脚本点不动页面。
2. **浏览器下载设置关两项**：`edge://settings/downloads` / `chrome://settings/downloads`（QQ：设置 → 下载）里关掉
   - 「**在下载之前询问每个文件的保存位置**」：不关每次弹系统「存储为」对话框，扩展点不掉 → **文件永远不落盘**；
   - 「**下载开始时显示下载菜单**」：不关每次弹下载浮层抢焦点、遮挡页面 → **干扰自动化翻页与下载进度判定**。
   - 建议顺手关「在浏览器中打开 Office 文件」，否则 CSV 会被浏览器直接打开而不落到下载目录。
3. `bash scripts/setup_browser_downloads.sh` 会自动改 Chrome/Edge 的两项 Preferences；**「下载菜单」「Office 文件」必须在设置页手动关**，改完**完全退出并重启浏览器**才生效。

![WorkBuddy 设置 → 智能体 → 浏览器操控与扩展安装](https://newphotobed.oss-cn-shanghai.aliyuncs.com/img/clipboard-2026-11-10T23-32-20-809Z-c6734de9.png)

![浏览器下载设置：关闭「询问保存位置」与「下载开始时显示下载菜单」](https://newphotobed.oss-cn-shanghai.aliyuncs.com/img/clipboard-2026-11-10T23-32-20-810Z-d8ddfcf8.png)

> 逐项说明与前置检查清单见 [`references/01-environment-setup.md`](references/01-environment-setup.md) 第零节。

> 📖 **安装步骤见** → [`references/01-environment-setup.md`](references/01-environment-setup.md)（macOS 实测；Windows / Linux 为未测试的推演流程，见第七节）

### 一键自检

```bash
bash scripts/selftest.sh           # 无浏览器静态自检（建议部署时先跑）
bash scripts/setup_env.sh          # 只检查（含守护进程 / 浏览器连接）
bash scripts/setup_env.sh --install # 缺失项自动安装
```

`selftest.sh` 退出码 0 只说明**静态检查通过**，不代表下载链路能跑通。

### 单公司下载

```bash
CLI=~/.workbuddy/binaries/python/envs/qqbrowser-ctl/bin/qqbrowser-skill
bash scripts/download_company.sh \
  --name 长江电力 --market sh --code 600900 \
  --dest "/Volumes/KIOXIA/上市公司研究/电力系统/01-发电运营（15家）" --years 10
```

### 批量下载（推荐：一条命令）

```bash
# 准备清单文件 companies.txt，每行一条：公司名|market|code（# 开头为注释）
#   华能国际|sh|600011
#   龙源电力|hk|00916
bash scripts/batch_download.sh --list companies.txt \
  --dest "/Volumes/KIOXIA/上市公司研究/电力系统/01-发电运营（15家）" --years 10
```

串行执行（浏览器单客户端，并行会抢会话），单家 5~7 分钟；日志落 `$LX_TMP/lx_batch_*.log`，
每家跑完即时打印失败项，不用等全跑完才发现前面全废。

<details>
<summary>手工循环版（想自己控制时用）</summary>

```bash
while IFS='|' read -r n m c; do
  bash scripts/download_company.sh --name "$n" --market "$m" --code "$c" --dest /path --years 10
done < companies.txt
```

</details>

---

## 🧠 核心技术点（为什么它稳）

| 点 | 做法 |
|---|---|
| **登录态复用** | 驱动已登录的 QQ 浏览器真实会话，不破解、不重登 |
| **URL 直达** | 日期范围写进 URL（`start-date`/`end-date`），**免点「10 年」按钮**（该按钮文字带空格，极易定位失败） |
| **弹窗 index 动态取** | 导出弹窗的选项 index 每次都变，脚本每次重新快照获取 |
| **员工数据兜底** | 该页 UI 导出在自动化下不触发 → 用 DOM 提取表格 + 本地生成 CSV |
| **跨盘归档** | 用 `cp` + `rm` 代替 `mv`（跨设备 `mv` 报 `EXDEV`） |
| **目录规范** | 按公司分子文件夹，PDF 分别进 `年报PDF/` 与 `招股资料/` |
| **验收盘真实落盘** | 退出码 0 ≠ 成功，批量后必须用 Python 盘目录（脚本内部失败不改退出码） |
| **IPO 分类取招股书** | 走 `announcement-type=ipo`，**不是** `search-key=招股说明书`（后者会漏掉「招股意向书」）|

> 详细机制见 [`references/02-lixinger-internals.md`](references/02-lixinger-internals.md)；踩坑与排查见 [`references/03-troubleshooting.md`](references/03-troubleshooting.md)；**多公司批量必读** [`references/04-batch-playbook.md`](references/04-batch-playbook.md)。

---

## 💡 四条血泪经验（价值最高的部分）

这四条都是真金白银换来的，任何一个不知道都会白干一轮：

**1. 退出码只看「失败项」，但 0 仍不等于齐全** —— 必须盘真实落盘
2026-11-10 起 `download_company.sh` 有失败项即 `exit 1`（此前 PDF 全断也是 0，改前真出过这事）。
但「理杏仁未收录 / 已存在跳过 / H股繁体替代」都不算失败，所以退出码 0 仍可能缺内容。
实测 12 家全部退出码 0，真盘却发现 **4 家整段 0 份 + 3 家零星缺年**。
批量后务必用 Python 盘一遍目录（模板见 `references/04` 第三节）。

**2. 招股书要用「IPO 分类」，别用关键词搜索**
`search-key=招股说明书` 只能命中标题写死"招股说明书"的，而老公司 IPO 时用的是
「**招股意向书**」，会被整批漏掉。改用公告页 IPO 分类才能覆盖齐全。

> 🔴 **但 IPO 分类只能"按需取用"，禁止全量灌**（老板 2026-09-19 明确要求）：
> 招股资料的取舍由老板人工筛选，他已把 17 家的 `招股资料/` 定稿为 **31 份**；
> IPO 分类下合计约 153 条，其中**大部分（发行/询价/中签/保荐/限售流通等程序性文件）不是他要的**。
> **脚本已硬化**：不带 `--include` 会直接报错退出。
> ```bash
> bash scripts/download_ipo.sh --name 中国神华 --market sh --code 601088 \
>      --dest "<目标目录>" --include 招股意向书,招股说明书
> ```
> 2026-09-19 我曾误做全量回填（28 → 158 份），多出的 127 份已移入
> `/Volumes/KIOXIA/理杏仁下载/_IPO移出_隔离区/`。

⚠️ IPO 列表是**异步渲染**的（实测需等约 15s），旧版只等 5s+3s 就采集，
会误报「IPO 分类下未匹配到文件」。脚本已加 `wait_ready` 轮询 + 首轮为 0 时重试。

**3. 补漏有优先级，两条路是死的**
`重跑 PDF 段` → `港交所 hkexnews 补` → `抓 href 走浏览器直下`。
❌ **curl 直下交易所链接**（防盗链）、❌ **巨潮 cninfo API**（当前返回空）——这两条别浪费时间。
港股补年报还有四坑：JSONP 剥壳、中文数字年份（「二零二零年年度報告」）、
`toDate` 要放宽到次年、`prefix.do` 会限流（建议硬编码 stockId）。

**4. 补漏幂等 + 空壳校验 + A 股优先（v2.1）**
补 3 个坏文件别整家重跑 —— 会白白重下 6 份有效 PDF。脚本已内置
**幂等**（已有效则跳过，`--only-years` 精准到年份）+ **空壳校验**
（`%PDF-` 头 + 体积双检，4KB 假文件直接拒收）+ **自动登录**
（`scripts/lixinger_login.sh` 读凭证填表提交，**切勿因未登录就换数据源**）。
年报另有两个正则坑：A 股「…年度报告**全文**」曾被整年漏抓、且会误抓成 **H 股繁体版**；
现规则 **A+H 公司优先 A 股**，仅当某年 A 股未收录才回退 H 股（每次下载都标注版本）。

---

## 📂 产品结构

```
lixinger-download/
├── README.md                            ← 给"人"看的使用说明（本文件）
├── SKILL.md                             ← 给"Agent"看的执行编排（三阶段流程）
├── references/
│   ├── 01-environment-setup.md          ← 环境安装（macOS 实测 / Windows 未测试的部署流程）
│   ├── 02-lixinger-internals.md         ← URL 模式、导出机制、各页面差异
│   ├── 03-troubleshooting.md            ← 坑位清单与排查决策树
│   └── 04-batch-playbook.md             ← 批量实战手册（验收盘点 / 补漏决策树 / 17家实测表）
└── scripts/
    ├── lib_platform.sh                  ← 平台抽象层（CLI/临时目录/主目录/Preferences）
    ├── selftest.sh                      ← 跨平台静态自检（无浏览器）
    ├── setup_env.sh                     ← 环境自检与一键安装
    ├── acceptance_windows.sh           ← 可选：一次性自检串跑（Windows 上从未运行过）
    ├── download_company.sh              ← 单公司完整下载主脚本（幂等 / --only-years / --force）
    ├── download_ipo.sh                  ← 招股/发行文件（IPO 分类）下载
    ├── batch_download.sh                ← 批量串行驱动（读清单文件，日志 + 即时播报）
    └── companies.example.json           ← 批量公司清单模板
```

---

## ⚠️ 边界（诚实交代）

### ✅ 能做到
- 一次配置，之后批量公司无人值守
- 数据口径与你账号能看到的一致（免费/会员均可）
- 目录规范、命名可读，直接拿去分析

### ⚠️ 边界
- **员工数据**：理杏仁该页 UI 导出按钮在自动化下不触发，脚本用 DOM 提取兜底（数据一致，格式为「指标 × 年份」矩阵，与官方导出略有差异）
- **PDF 年份**：依赖页面可见的年报链接（通常最近 10 年），更早年份需另行寻找
- **登录态会过期**：下载脚本开会话前自动调用 `scripts/lixinger_login.sh`（读凭证填表提交）；仅当凭证缺失或账号到期时才需人工处理
- **平台**：**仅 macOS 真机实测通过；Windows / Linux 从未测试过**。代码含平台适配层，但**不保证能跑通**。Windows 上 `.sh` 只能用 Git Bash / MSYS2 / WSL 执行，流程见 [`references/01-environment-setup.md`](references/01-environment-setup.md) 第七节

### ❌ 做不到
- 不能在**凭证文件缺失且浏览器无残留登录态**的全新环境下工作（需先写 `creds.json` 或人工登录一次）
- 不能绕过理杏仁的会员权限（用你能看的数据）

---

## ❓ 常见问题

**Q: 会不会被封号？**
A: 脚本每次导出间隔 ≥5 秒，模拟人工节奏，克制访频；正常使用风险很低。

**Q: 要花钱吗？**
A: 不用。全程本地浏览器 + 开源工具，**0 成本**。

**Q: 支持港股/美股吗？**
A: 理杏仁支持 A 股（`sh`/`sz`）、港股（`hk`）等；市场段按理杏仁 URL 规则填即可。

**Q: 换台电脑怎么办？**
A: 按 [`references/01-environment-setup.md`](references/01-environment-setup.md) 装 Python + `qqbrowser-skill` + QQ 浏览器，再一次性写入 `~/.config/lixinger-download/creds.json`（之后脚本自动登录，无需再管）。

**Q: 补漏会不会把已下好的文件又重下一遍？**
A: 不会。脚本**幂等**：已存在且校验通过的 PDF 直接跳过，只补缺失/损坏的年份；
加 `--only-years 2023,2024` 可精准到年份，`--force` 才强制覆盖（版本升级用）。

---

## 📝 版本

| 版本 | 说明 |
|---|---|
| **v2.2**（当前） | **跨平台抽象** `lib_platform.sh`（CLI 路径 / 临时目录 / 主目录 / Preferences / 盘符校验）+ `selftest.sh` 无浏览器静态自检 + 全部脚本去除 `/tmp` 与 `bin/` 硬编码 + `.gitattributes` CRLF 防护 + 自动登录接入主链路 + 翻页签名判据修复 + 阶段 0 六个 bug 修复。**仅 macOS 实测；Windows / Linux 未测试** |
| v2.1 | **幂等补漏**（已有效文件跳过，不重复下载）· **空壳校验**（`%PDF-` + 体积双检，拒收 4KB 假文件）· **自动登录**（`creds.json` + `lixinger_login.sh` 填表提交）· **A 股优先规则**（A+H 公司优先 A 股年报）· 年报正则修复（不再漏「全文」年份 / 不再抓成 H 股繁体版）· 滚动范围扩到 12000px · 新增 `--only-years` / `--force` · 新增 `download_ipo.sh` · 员工数据 CSV 去日期 |
| v2.0 | **IPO 招股/发行文件批量下载**（`announcement-type=ipo`）· 批量串行驱动脚本 `batch_download.sh` · 批量实战手册 `04-batch-playbook.md` · **验收盘点与补漏决策树** · 港股年报补漏（hkexnews 坑位全记录）· 目录规范加 `招股资料/` 子层 |
| v1.0 | 三阶段流程（环境→单公司→批量）· URL 直达免点按钮 · 员工数据 DOM 兜底 · 跨平台环境文档 · 命名与目录规范 |

---

## 👤 作者与许可

**作者**：松幽（SongYouAI）

- 📱 公众号：**松幽舒苑**
- 🎬 视频号：**松幽Ai提效**

**License**：MIT — 可自由使用、修改、分发，保留出处即可。

> 数据版权同理杏仁，请遵守其服务条款；本 Skill 仅自动化你本人有权查看的数据导出。
