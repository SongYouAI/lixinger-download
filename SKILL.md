---
name: lixinger-download
description: 理杏仁(lixinger.com)财报批量自动下载。当用户要下载理杏仁的公司财报/Excel/CSV/年报PDF、批量抓取财务数据时使用。驱动已登录的 QQ 浏览器自动导出资产负债表、利润表、现金流量表、财务指标、营收构成、经营数据、员工数据(7类CSV,均10年) + 10年PDF年报，按「公司/年报PDF」目录结构归档。无人值守，全程免费。
agent_created: true
---

# 理杏仁财报批量下载

用浏览器自动化接管**已登录理杏仁**的浏览器，按公司批量导出 7 类财报 CSV（10 年）+ 10 份年报 PDF，自动归档到规范目录。

> 本 skill 的所有流程与坑位均来自**真机实测**（macOS + QQ 浏览器 + 长江电力完整跑通）。

## 触发场景

- "下载 XX 公司的理杏仁财报"
- "批量导出理杏仁财报 Excel / CSV"
- "自动下载年报 PDF"
- 任何涉及 lixinger.com 数据导出的自动化需求

---

## 三阶段执行（**严禁跳过阶段 1、2 直接批量**）

| 阶段 | 目标 | 通过标准 |
|------|------|---------|
| **1. 环境准备** | 装依赖、起守护进程、确认登录态 | `setup_env.sh` 全绿 |
| **2. 单公司验证** | 用 1 家公司跑完整流程 | 7 CSV + 10 PDF 齐全且数据正确 |
| **3. 批量** | 按公司清单循环 | 每家独立子文件夹，互不影响 |

> ⚠️ 老板铁律：**先小范围验证再批量**。阶段 2 没跑通，不许进阶段 3。

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

```bash
# 编辑公司清单后循环调用
bash scripts/download_company.sh --name 贵州茅台 --market sh --code 600519 --dest /path --years 10
```

公司清单模板：`scripts/companies.example.json`

---

## 硬约束（必须遵守）

| 约束 | 说明 |
|------|------|
| **必须免费** | 所有工具均为开源/免费，禁止使用任何付费 API 或付费 LLM |
| **登录态** | 理杏仁账号需**手动登录一次**（脚本无法登录），cookie 持久化后即可无人值守 |
| **频率克制** | 每次导出间隔 ≥5 秒，避免触发风控/验证码 |
| **目录规范** | 见下方，禁止平铺 |
| **文件命名** | 必须带公司名前缀（理杏仁原始名如 `600900_20260430_WC8R.pdf` 完全不可读） |

### 输出目录规范

```
{目标根目录}/
├── 长江电力/
│   ├── 年报PDF/                              ← PDF 单独子层
│   │   ├── 长江电力_2016年年度报告.pdf
│   │   └── …（共 10 年）
│   ├── 长江电力_资产负债表_合并报表_*.csv
│   ├── 长江电力_利润表_合并报表_*.csv
│   ├── 长江电力_现金流量表_合并报表_*.csv
│   ├── 长江电力_财务指标_合并报表_*.csv
│   ├── 长江电力_营收构成_*.csv
│   ├── 长江电力_经营数据_*.csv
│   └── 长江电力_员工数据_全体员工_*.csv
└── 下一家公司/
```

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
| `announcement?search-key=年度报告` | 公告筛选页（**年报 PDF 在这里**） |

**导出三连**：点「导出CSV」→ 选「壹」→ 点「时间横排 - 降序」→ 自动下载

> ⚠️ **例外**：经营数据(`operating-data`) 弹窗**没有「壹」单位选项**（该表单位固定）。若卡在"找不到单位"直接跳过选单位、点排序即可下载。

---

## 参考文件

| 文件 | 何时读 |
|------|--------|
| `references/01-environment-setup.md` | **新电脑/新环境必读**——详细安装步骤（macOS/Windows/Linux）、依赖版本、登录态准备 |
| `references/02-lixinger-internals.md` | 写脚本或流程出错时——URL 模式、导出机制、各页面差异、完整命令 |
| `references/03-troubleshooting.md` | 报错/下载失败时——坑位清单与排查决策树 |
| `scripts/setup_env.sh` | 环境自检与一键安装 |
| `scripts/download_company.sh` | 单公司完整下载主脚本（参数化） |
| `scripts/companies.example.json` | 批量公司清单模板 |

---

## 已知限制

- **员工数据**：理杏仁该页 UI 导出按钮在自动化下不触发下载，脚本用 **DOM 提取表格 + 本地生成 CSV** 兜底（数据内容一致，格式为「指标 × 年份」矩阵，与官方导出格式略有差异）
- **QQ 浏览器通道**为实测验证路径；Chrome + Playwright 为备选路径（见环境文档，需自行调试）
- 年报 PDF 从「**公告**」筛选页（`announcement?search-key=年度报告`，关键词需 URL 编码）精确匹配获取，通常可见最近 10 年，更早年份需另行寻找
  - ⚠️ 年报链接**不在**员工页 / 经营数据页（那些页面只有临时公告），从错误页面 grep 必然 0 命中
