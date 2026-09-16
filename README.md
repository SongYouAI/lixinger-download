# 理杏仁财报批量下载

> **一句话**：告诉它公司名，它自动从 [理杏仁](https://www.lixinger.com) 把这家公司的 **7 类财报 CSV（10 年）+ 10 年 PDF 年报** 全套下载好，按「公司 / 年报PDF」规范归档。**无人值守、全程免费。**

一个把「重复下载财报」这件苦力活沉淀成资产的 WorkBuddy Skill。驱动**你已登录理杏仁的 QQ 浏览器**，复用真实登录态，模拟人工完成「翻页 → 导出 → 归档」全流程。

> 本 Skill 的所有流程与坑位均来自**真机实测**（macOS + QQ 浏览器 + 长江电力完整跑通），不是纸上方案。

---

## 🧭 这是什么 / 给谁用

| 项 | 说明 |
|---|---|
| **主要平台** | **WorkBuddy**（放入 `~/.workbuddy/skills/lixinger-download/` 即可被识别调用） |
| **其他 Agent** | **兼容**。`SKILL.md` 为标准 Agent Skill 格式，Claude Code / Cline 等支持 `SKILL.md` 约定的 Agent 均可加载；脚本为纯 Bash + Python，跨 macOS / Windows / Linux |
| **给谁用** | 需要**批量下载上市公司财报**做分析的价值投资者、财务研究者、投研从业者 |
| **输入** | 公司名 + 股票代码（市场段 `sh`/`sz`/`hk`） |
| **产物** | 每家公司一个文件夹：7 类 CSV（资产负债表/利润表/现金流量表/财务指标/营收构成/经营数据/员工数据，均 10 年）+ `年报PDF/` 下 10 份年报 |
| **成本** | **0 元**。全程用本地已登录浏览器 + 开源工具，不接任何付费 API |
| **不是** | 不是爬虫集群、不是云端服务、不绕过任何会员权限（用你自己的理杏仁账号看你能看的数据） |

---

## ✨ 每家公司的标准产出（8 类）

```
{目标目录}/{公司}/
├── 年报PDF/                                  ← PDF 单独子层，整齐
│   ├── {公司}_2016年年度报告.pdf
│   └── …（共 10 年）
├── {公司}_资产负债表_合并报表_*.csv           ← 10 年
├── {公司}_利润表_合并报表_*.csv
├── {公司}_现金流量表_合并报表_*.csv
├── {公司}_财务指标_合并报表_*.csv
├── {公司}_营收构成_*.csv
├── {公司}_经营数据_*.csv
└── {公司}_员工数据_全体员工_*.csv
```

**文件命名**：所有文件强制带**公司名前缀**——理杏仁原始名（如 `600900_20260430_WC8R.pdf`）完全不可读，Skill 会自动重命名。

---

## 🎯 触发场景

```
下载 XX 公司的理杏仁财报 / 批量导出理杏仁财报 Excel / 自动下载年报 PDF
把 XX 的十年财报全下载下来 / 理杏仁财报批量抓取
```

**用法示例**：
> 「用 **理杏仁财报批量下载** 把长江电力（sh 600900）近十年财报下载到 `/Volumes/KIOXIA/理杏仁下载`」

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
| 理杏仁账号 | **必须手动登录一次**（登录态存浏览器 cookie，之后无人值守复用） |

> 📖 **完整安装细节（macOS / Windows / Linux 三平台）见** → [`references/01-environment-setup.md`](references/01-environment-setup.md)

### 一键自检

```bash
bash scripts/setup_env.sh          # 只检查
bash scripts/setup_env.sh --install # 缺失项自动安装
```

### 单公司下载

```bash
CLI=~/.workbuddy/binaries/python/envs/qqbrowser-ctl/bin/qqbrowser-skill
bash scripts/download_company.sh \
  --name 长江电力 --market sh --code 600900 \
  --dest "/Volumes/KIOXIA/理杏仁下载" --years 10
```

### 批量下载

编辑公司清单（模板见 [`scripts/companies.example.json`](scripts/companies.example.json)）后循环调用：

```bash
jq -r '.companies[] | "\(.name) \(.market) \(.code)"' companies.json | \
while read n m c; do
  bash scripts/download_company.sh --name "$n" --market "$m" --code "$c" --dest /path --years 10
done
```

---

## 🧠 核心技术点（为什么它稳）

| 点 | 做法 |
|---|---|
| **登录态复用** | 驱动已登录的 QQ 浏览器真实会话，不破解、不重登 |
| **URL 直达** | 日期范围写进 URL（`start-date`/`end-date`），**免点「10 年」按钮**（该按钮文字带空格，极易定位失败） |
| **弹窗 index 动态取** | 导出弹窗的选项 index 每次都变，脚本每次重新快照获取 |
| **员工数据兜底** | 该页 UI 导出在自动化下不触发 → 用 DOM 提取表格 + 本地生成 CSV |
| **跨盘归档** | 用 `cp` + `rm` 代替 `mv`（跨设备 `mv` 报 `EXDEV`） |
| **目录规范** | 按公司分子文件夹，PDF 单独进 `年报PDF/` |

> 详细机制见 [`references/02-lixinger-internals.md`](references/02-lixinger-internals.md)；踩坑与排查见 [`references/03-troubleshooting.md`](references/03-troubleshooting.md)。

---

## 📂 产品结构

```
lixinger-download/
├── README.md                            ← 给"人"看的使用说明（本文件）
├── SKILL.md                             ← 给"Agent"看的执行编排（三阶段流程）
├── references/
│   ├── 01-environment-setup.md          ← 环境安装（macOS/Win/Linux 三平台）
│   ├── 02-lixinger-internals.md         ← URL 模式、导出机制、各页面差异
│   └── 03-troubleshooting.md            ← 坑位清单与排查决策树
└── scripts/
    ├── setup_env.sh                     ← 环境自检与一键安装
    ├── download_company.sh              ← 单公司完整下载主脚本（参数化）
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
- **登录态会过期**：理杏仁 token 过期后需**手动重登一次**（脚本无法代登）

### ❌ 做不到
- 不能在未登录状态下工作（必须真人先登录一次）
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
A: 按 [`references/01-environment-setup.md`](references/01-environment-setup.md) 装 Python + `qqbrowser-skill` + QQ 浏览器，再手动登录一次理杏仁即可。

---

## 📝 版本

| 版本 | 说明 |
|---|---|
| 当前版 | 三阶段流程（环境→单公司→批量）· URL 直达免点按钮 · 员工数据 DOM 兜底 · 跨平台环境文档 · 命名与目录规范 |

---

## 👤 作者与许可

**作者**：松幽（SongYouAI）

- 📱 公众号：**松幽舒苑**
- 🎬 视频号：**松幽Ai提效**

**License**：MIT — 可自由使用、修改、分发，保留出处即可。

> 数据版权同理杏仁，请遵守其服务条款；本 Skill 仅自动化你本人有权查看的数据导出。
