# 环境安装与准备（新电脑必读）

> 目标：**任何一台电脑、任何一个 Agent**，照着本文都能把环境装好并跑通。
> 本文覆盖 macOS / Windows / Linux 三平台，每步都给可直接复制的命令。

---

## 一、依赖总览

| # | 依赖 | 版本要求 | 用途 | 是否必须 |
|---|------|---------|------|:---:|
| 1 | Python | ≥ 3.9（推荐 3.11+） | 运行 qqbrowser-skill CLI | ✅ 必须 |
| 2 | Python venv | 随 Python 自带 | 隔离依赖，不污染系统 | ✅ 推荐 |
| 3 | `qqbrowser-skill` | 最新 | 浏览器自动化 CLI（Python 包） | ✅ 必须（主通道） |
| 4 | QQ 浏览器 | 最新版 | 被驱动的浏览器 | ✅ 必须（主通道） |
| 5 | 理杏仁账号 | 已注册（免费/会员均可） | 登录态 | ✅ 必须 |
| 6 | Chrome + Playwright | 备选 | 无 QQ 浏览器时的回退路径 | ⭕ 备选 |

---

## 二、安装步骤

### 步骤 1：确认 Python

```bash
python3 --version
# 需 ≥ 3.9。若低于或不存在，先装：
#   macOS  : brew install python@3.11   （需先装 Homebrew）
#   Windows: 到 python.org 下载安装，**务必勾选 Add Python to PATH**
#   Ubuntu : sudo apt update && sudo apt install -y python3 python3-venv
```

### 步骤 2：创建隔离虚拟环境

> 强烈建议隔离，避免污染系统 Python 或其他 skill 的依赖。
> 本 skill 后续默认环境路径：`~/.workbuddy/binaries/python/envs/qqbrowser-ctl`

```bash
# 定义路径（macOS/Linux）
VENV=~/.workbuddy/binaries/python/envs/qqbrowser-ctl
mkdir -p "$(dirname "$VENV")"
python3 -m venv "$VENV"

# Windows (PowerShell)
# $VENV = "$env:USERPROFILE\.workbuddy\binaries\python\envs\qqbrowser-ctl"
# python -m venv $VENV
```

### 步骤 3：安装 qqbrowser-skill CLI

```bash
"$VENV/bin/pip" install -q qqbrowser-skill
# Windows: "$VENV\Scripts\pip.exe" install -q qqbrowser-skill

# 验证（注意：--version 不支持，用 --help 验证）
"$VENV/bin/qqbrowser-skill" --help | head -20
```

> 💡 **重要**：技能商店安装的往往只是 SKILL.md 说明书，**CLI 本体需要自行 pip 安装**。
> 若提示找不到包，先升级 pip：`"$VENV/bin/pip" install -U pip`

### 步骤 4：安装 QQ 浏览器（主通道）

| 系统 | 下载 |
|------|------|
| macOS | https://browser.qq.com/mac/ |
| Windows | https://browser.qq.com/ |
| Linux | QQ 浏览器无官方 Linux 版 → **走备选通道（Playwright + Chrome）** |

安装完成后**打开一次 QQ 浏览器**，让它完成初始化。

### 步骤 5：登录理杏仁（首次手动一次；之后可自动恢复）

首次需在 QQ 浏览器打开 https://www.lixinger.com 手动登录一次，勾选"记住我"
（**账号密码会保存在浏览器里**，这是后续自动登录的前提）。

> ✅ **之后无需再手动**：`download_company.sh` / `download_ipo.sh` 内置 `login_if_needed()`，
> 检测到未登录会**自动点击右上角「登录/注册」**——账号密码已存于浏览器，**一点即登录**。
> （老板 2026-09-19 亲授）
>
> ⛔ **切勿因未登录就换数据源！** 2026-09-19 实测绕去东方财富 / 巨潮 cninfo / 上交所 / 新浪
> **全部碰壁**（东财把年报路由到「一张图读懂」信息图、cninfo 与 SSE API 均 500、新浪 Service not valid），
> 白白浪费十几轮排查。正确动作只有两个：**自动点击登录** → 失败才**手动登录一次**。
>
> 验证登录态：访问首页会跳转到个人中心（`https://www.lixinger.com/profile/center/...`）。

### 步骤 6：启动守护进程

```bash
"$VENV/bin/qqbrowser-skill" serve --daemon
"$VENV/bin/qqbrowser-skill" status
# 期望输出：✅ Daemon is running / Connected clients: 1
```

> 守护进程是 CLI 与浏览器之间的桥梁，**每次开机后需重新启动**（或设为开机自启）。
> 首次启动时它可能关闭并重开浏览器，属正常行为，登录态不会丢失。

---

## 三、一键自检（推荐）

```bash
bash ~/.workbuddy/skills/lixinger-download/scripts/setup_env.sh
```

脚本会逐项检查并明确报告：
- ✅ Python 版本
- ✅ venv 是否存在
- ✅ qqbrowser-skill CLI
- ✅ QQ 浏览器 / Chrome 是否安装
- ✅ 守护进程状态
- ✅ 浏览器连接数

任何一项 ❌ 都会给出修复命令。**全部 ✅ 才能进入下载阶段。**

---

## 四、备选通道：无 QQ 浏览器时（Playwright + Chrome）

> 状态：⚠️ **本路径未在理杏仁场景完整实测**，需自行调试，作为无 QQ 浏览器时的回退方案。

```bash
PWVENV=~/.workbuddy/binaries/python/envs/lixinger-pw
python3 -m venv "$PWVENV"
"$PWVENV/bin/pip" install -q playwright
"$PWVENV/bin/python" -m playwright install chromium
```

**登录态处理**：复制 Chrome 的 Default profile 到临时目录，用副本启动（避免与原浏览器冲突）：

```bash
cp -R ~/Library/Application\ Support/Google/Chrome/Default /tmp/chrome-profile-lixinger
# 用 Playwright 的 launch_persistent_context(user_data_dir="/tmp/chrome-profile-lixinger") 启动
```

> macOS 上 Chrome 需在关闭状态下复制 profile，否则可能拿到损坏的副本。

---

## 五、验收 Checklist（进入下载前的最后确认）

- [ ] `python3 --version` ≥ 3.9
- [ ] venv 已创建，qqbrowser-skill CLI 可执行
- [ ] QQ 浏览器已安装且能正常打开网页
- [ ] **理杏仁已登录**（首次手动一次；之后脚本会自动恢复。访问首页会跳个人中心）
- [ ] `qqbrowser-skill status` 显示 `Daemon is running` 且 `Connected clients ≥ 1`
- [ ] 目标磁盘有足够空间（每家公司约 30 MB：CSV 约 150 KB + PDF 约 28 MB）

---

## 六、常见安装问题

| 现象 | 原因 / 解决 |
|------|------------|
| `command not found: qqbrowser-skill` | 未装 CLI 或没用绝对路径 → 用 `$VENV/bin/qqbrowser-skill` |
| `pip: command not found` | 用 `"$VENV/bin/python" -m pip` 代替 |
| 守护进程起不来 | 检查端口 8765/8766 是否被占；重启浏览器后再试 |
| `Connected clients: 0` | 浏览器未连上 → 关闭浏览器重开，或重新 `serve --daemon` |
| 页面显示"加载数据失败" | URL 格式错误（见 internals 文档）或登录态过期 |
| Windows 上路径报错 | 用 PowerShell 语法，路径中的 `\` 需注意转义 |
