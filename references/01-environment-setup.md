# 环境安装与准备（新电脑必读）

> 目标：照着本文把环境装好并跑通。
>
> 🔴 **测试范围（先看这条）**：本 skill **只在 macOS + QQ 浏览器上真机实测过**；
> **Windows / Linux 从未在真机上跑过一次**，能不能用、会踩什么坑，都不知道。
> 下面 Windows / Linux 的命令是**按代码推演的部署步骤，不是验证过的方案**。
>
> 🔴 **Windows 终端约束**：本 skill 全是 `.sh`（bash）脚本，只能在 **Git Bash / MSYS2 / WSL** 里跑。
> **PowerShell / CMD 不能执行 `.sh`**。下文命令默认以 Git Bash 为准。

---

## 零、前置设置（必做，漏一项就卡住整个流程）

> 这一节比装 Python 还靠前：它决定**浏览器自动化能不能跑起来**。
> 三件事：**打开 WorkBuddy 浏览器控制 → 装浏览器扩展 → 关掉下载设置里的两个开关**。
> 截图来自 2026-11-11 真机（macOS），三浏览器设置页大同小异。

### 0.1 打开 WorkBuddy 设置里的「浏览器控制」

打开 **WorkBuddy 设置 → 智能体 → 浏览器操控（Beta）**：

1. 把「**让 WorkBuddy 控制浏览器**」开关打开（右侧变绿）。
2. 在下面给要用的浏览器装扩展，**用到的那个必须显示绿点「已安装」**：
   - `WorkBuddy Chrome 扩展程序`
   - `WorkBuddy Edge 扩展程序`
   - `WorkBuddy QQ 浏览器扩展程序`
3. 若「无法访问扩展商店」，点右侧「**手动安装**」——通过开发者模式加载扩展，适用于 Chrome / Edge / QQ 等 Chromium 内核浏览器。

![WorkBuddy 设置 → 智能体 → 浏览器操控](https://newphotobed.oss-cn-shanghai.aliyuncs.com/img/clipboard-2026-11-10T23-32-20-809Z-c6734de9.png)

> 不开这个开关 → CLI `status` 显示 `Connected clients: 0`，所有下载脚本都点不动页面。
> 主通道是 **QQ 浏览器**；Chrome / Edge 是备选通道（能力边界见 `05-browser-matrix.md`），至少装你要用的那一个。

### 0.2 关掉浏览器下载设置里的两个开关

进入下载设置页：Edge `edge://settings/downloads`、Chrome `chrome://settings/downloads`（QQ 浏览器在「设置 → 下载」）。

![浏览器下载设置：关闭两项](https://newphotobed.oss-cn-shanghai.aliyuncs.com/img/clipboard-2026-11-10T23-32-20-810Z-d8ddfcf8.png)

**这两项必须关**（截图红框）：

| 开关 | 不关会怎样 |
|---|---|
| **在下载之前询问每个文件的保存位置** | 每次下载都弹系统「存储为」对话框，**扩展点不掉它 → 文件永远不落盘**（实测连点三次全无反应）；脚本只会一直等文件，最后判定「未检测到下载」 |
| **下载开始时显示下载菜单** | 每次下载弹出下载浮层/菜单，抢焦点、遮挡页面，直接干扰自动化翻页与下载进度判定 |

另外建议关掉「**在浏览器中打开 Office 文件**」：否则 CSV 可能被浏览器直接打开而不落到下载目录，脚本就找不到文件。

> `scripts/setup_browser_downloads.sh` 会自动改 Chrome/Edge Preferences 里的
> `download.prompt_for_download=false` 和 `plugins.always_open_pdf_externally=true`，
> 但**「下载开始时显示下载菜单」「在浏览器中打开 Office 文件」要在设置页手动关**。
> `bash scripts/setup_browser_downloads.sh --check` 可看前两项当前值；改完必须**完全退出并重启浏览器**才生效。

### 0.3 前置检查清单

- [ ] WorkBuddy 设置 → 智能体 → 「让 WorkBuddy 控制浏览器」已开启
- [ ] 目标浏览器的 WorkBuddy 扩展显示「已安装」
- [ ] 下载设置里两项已关闭（Office 文件那项也已关）
- [ ] `qqbrowser-skill status` 显示 `Daemon is running` 且 `Connected clients ≥ 1`

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
# macOS / Linux / Windows Git Bash 通用
VENV="$HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl"
mkdir -p "$(dirname "$VENV")"
python3 -m venv "$VENV"
```

### 步骤 3：安装 qqbrowser-skill CLI

```bash
"$VENV/bin/pip" install -q qqbrowser-skill
# Windows Git Bash（venv 在 Scripts/）:
#   "$VENV/Scripts/pip.exe" install -q qqbrowser-skill
# 脚本会自动探测 bin/ 与 Scripts/，不需要手工指定 CLI 路径。

# 验证（注意：--version 不支持，用 --help 验证）
"$VENV/bin/qqbrowser-skill" --help | head -20
# Windows: "$VENV/Scripts/qqbrowser-skill.exe" --help | head -20
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

### 步骤 5：写入理杏仁账号（一次性，自动登录前提）

#### 账号密码从哪来 —— **使用者自己提供，本 skill 不附带任何账号**

| 项 | 说明 |
|---|---|
| **谁提供** | **使用者自己**。本 skill 与本仓库**不含任何理杏仁账号密码**，也不代购、不代注册 |
| **怎么交给 Agent** | 最省事的做法：**直接把账号和密码发给 Agent**，让它按下面格式写进 `creds.json`（仓库外、权限 600、已 gitignore）。之后 `scripts/lixinger_login.sh` 会自己判登录态、填表、提交，**你不用手工登录 QQ 浏览器**；账号过期换号时，改这个文件重跑即可 |
| **获取渠道** | ① **官方渠道**：理杏仁官网注册 / 购买会员，稳定、有售后；② **二手交易平台**（俗称「海鲜市场」，即闲鱼）：常见共享号 / 租借号，便宜但**有效期短、容易过期，且有账号安全与合规风险**，请自行判断并承担后果 |
| **⛔ 绝不能做** | 把真实账号密码写进 `SKILL.md`、提交到 Git、贴到公开 Issue 或群里 —— **本仓库是公开的**，push 出去就等于泄露 |

> 会员权限决定你能看到的数据范围，脚本不会绕过。账号到期最直接的表现是自动登录失败或页面提示会员过期，
> 按 `03-troubleshooting.md` 第六节排查，**不要因为未登录就换数据源**。

在 `~/.config/lixinger-download/creds.json` 写入账号密码（**仓库外 + 已 gitignore，权限 600**）：

```bash
mkdir -p ~/.config/lixinger-download
cat > ~/.config/lixinger-download/creds.json <<'EOF'
{"account":"手机号","password":"密码"}
EOF
chmod 600 ~/.config/lixinger-download/creds.json
```

> ✅ **之后无需人工登录**：`download_company.sh` / `download_ipo.sh` 开会话前自动调用
> `scripts/lixinger_login.sh`。它读凭证、判登录态、必要时填表并提交。
> 判据：**页面文本含账号 = 已登录**；「登录/注册」链接在已登录态也可能残留，不能用它判。
> 就绪判据是「状态明确为 `IN`/`OUT`」，不是文本长度 —— 半渲染的骨架态会返回 `UNK`，
> 此时脚本会重载重试一次，仍 `UNK` 就明确报错（详见 `03-troubleshooting.md` 第六节）。
>
> ⛔ **切勿因未登录就换数据源！** 2026-09-19 实测绕去东方财富 / 巨潮 cninfo / 上交所 / 新浪
> **全部碰壁**（东财把年报路由到「一张图读懂」信息图、cninfo 与 SSE API 均 500、新浪 Service not valid），
> 白白浪费十几轮排查。正确动作：**跑 `lixinger_login.sh`** → 失败才检查凭证/账号是否到期。
>
> 验证登录态：`bash scripts/lixinger_login.sh --check`（输出 `当前状态: IN` 即正常）。

### 步骤 6：启动守护进程

```bash
"$VENV/bin/qqbrowser-skill" serve --daemon
"$VENV/bin/qqbrowser-skill" status
# Windows: 把 bin/qqbrowser-skill 换成 Scripts/qqbrowser-skill.exe
# 期望输出：✅ Daemon is running / Connected clients: 1
```

> 守护进程是 CLI 与浏览器之间的桥梁，**每次开机后需重新启动**（或设为开机自启）。
> 首次启动时它可能关闭并重开浏览器，属正常行为，登录态不会丢失。

---

## 三、一键自检（推荐）

```bash
bash scripts/selftest.sh            # 无浏览器静态自检（建议部署时先跑）
bash scripts/setup_env.sh           # 环境自检（含守护进程、浏览器连接）
bash scripts/setup_env.sh --install # 缺失项自动安装
```

`selftest.sh` 检查平台识别、`LX_*` 变量、全部 `.sh` / `.py` 语法、
**shell 写 → Python 读的临时目录一致性**（Windows 最容易断的一项）、UTF-8 中文、
绝对路径/盘符转换、残留平台硬编码、`.gitattributes`。
**退出码 0 只说明静态检查通过，不代表下载链路能跑通**（Windows 尤其如此）。

`setup_env.sh` 会逐项检查并明确报告：
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

**登录态处理**（以下为 **macOS 路径示例**；Windows 的 profile 在 `%LOCALAPPDATA%/Google/Chrome/User Data/Default`）：复制 Chrome 的 Default profile 到临时目录，用副本启动（避免与原浏览器冲突）：

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
- [ ] `creds.json` 已写入，`bash scripts/lixinger_login.sh --check` 输出 `当前状态: IN`
- [ ] `bash scripts/selftest.sh` 退出码 0（静态检查，非可用性证明）
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
| PowerShell 里执行 `.sh` 报错 | PowerShell 不能执行 `.sh`；改用 Git Bash / MSYS2 / WSL |
| `$'\r': command not found` | `.sh` 变成 CRLF。仓库已带 `.gitattributes`（`*.sh text eol=lf`）；重新 clone 或执行 `git add --renormalize .` |
| Windows 上 shell 写的文件 Python 读不到 | `lib_platform.sh` 已把 `LX_TMP` 统一成 `C:/...` 形式；跑 `selftest.sh` 第 5 项确认 |
| `qqbrowser-skill.exe: Permission denied`(126) / 「已被组织 Device Guard 阻止」(199) | WDAC 拦截未签名 pip launcher → 用 `scripts/qqbrowser_skill_cli.sh`；`lib_platform.sh` 已自动切换 |
| `setup_env.sh --install` 报 `bin/pip: No such file or directory` | 旧版在创建 venv 前就把 pip 路径快照成 `bin/`；v2.2-winfix 已在建 venv 后重新探测 |
| 年报 PDF 全部「归档失败」 | venv 缺 `pymupdf`（或解释器候选漏了 `Scripts/python.exe`）→ `Scripts/python.exe -m pip install pymupdf` |
| `serve --daemon` 报 `QQ Browser is not installed` | CLI 硬前置；需管理员权限安装 QQ 浏览器，再在 WorkBuddy 设置里开启浏览器控制并装扩展 |

---

## 七、Windows 部署流程（v2.2-winfix · 已在 Windows 真机验证）

> ✅ **2026-11-12 更新**：本节命令已在 **Windows 11 / Git Bash (MINGW64) / Python 3.13** 真机跑过，
> 并据此修复了 5 处 Windows 兼容缺陷（详见交付的《Windows 验证与修复报告》）。
> 已验证：平台识别、路径转换、UTF-8 中文、静态自检、venv/CLI 安装、CLI 实调、
> 两道 Python 验收脚本、PDF 平台原语。
> 🔴 **仍未验证**：端到端真实下载。因为 `qqbrowser-skill serve --daemon` 强制要求
> 已安装 QQ 浏览器，且安装需管理员权限 + 需在 WorkBuddy 设置里开启浏览器控制并安装扩展。
> 这三项属于使用者侧前置，不是脚本缺陷；补齐后按步骤 6 验收即可。

### 支持范围（v2.2-winfix 实测）

| 终端 | 说明 |
|---|---|
| Git Bash（Git for Windows）/ MSYS2 | ✅ 静态自检 / 环境自检 / CLI 实调 已实测通过 |
| WSL | 未测；WSL 与 Windows 侧浏览器扩展的跨边界通信尤其不确定 |
| PowerShell / CMD | 不能执行 `.sh`，不支持 |

### 平台差异（由 `scripts/lib_platform.sh` 自动处理，不用手工改脚本）

| 项 | macOS（已实测） | Windows Git Bash（推演） |
|---|---|---|
| CLI | `$VENV/bin/qqbrowser-skill` | `scripts/qqbrowser_skill_cli.sh`（wrapper，见下方 🔴 说明）；`.exe` 仅作兜底 |
| pip | `$VENV/bin/pip` | `$VENV/Scripts/pip.exe` |
| 临时目录 | `$TMPDIR` 或 `/tmp` | `TEMP`/`TMP` 转成 `C:/...` 正斜杠形式 |
| 主目录 | `$HOME` | `USERPROFILE` 转 `C:/...`（避免 `/c/...` 传给原生 Python） |
| Chrome Preferences | `~/Library/Application Support/Google/Chrome/Default` | `%LOCALAPPDATA%/Google/Chrome/User Data/Default` |
| Edge Preferences | `~/Library/Application Support/Microsoft Edge/Default` | `%LOCALAPPDATA%/Microsoft/Edge/User Data/Default` |
| 关闭浏览器 | `osascript` + `killall -TERM` | `taskkill /IM /T /F`（Windows 无 SIGTERM 等价物） |
| 绝对路径 | `/abs/path` | `/abs/path`、`C:/abs/path`、`C:\abs\path` 均认 |
| 孤儿暂存 | `~/Library/Caches/lixinger-download/orphans` | `%LOCALAPPDATA%/lixinger-download/orphans` |

### 部署步骤

1. **把 skill 目录拷过去**：当前改动只在 Mac 本地、未 push，不能 `git clone`。用 U 盘 / 网盘 / 局域网把整个
   `~/.workbuddy/skills/lixinger-download/` 文件夹复制到 Windows，例如
   `C:/Users/<你>/.workbuddy/skills/lixinger-download`。
   **保留 `.gitattributes` / `.gitignore`；`.sh` 必须保持 LF** —— 别用记事本另存，否则变 CRLF 并报
   `$'\r': command not found`。
2. **装软件**：Python ≥3.9（**勾选 Add Python to PATH**）、Git for Windows、QQ 浏览器；浏览器先打开一次完成初始化。
3. **建 venv、装 CLI、起守护进程**（以下都在 **Git Bash** 里执行）：

   ```bash
   VENV="$HOME/.workbuddy/binaries/python/envs/qqbrowser-ctl"
   mkdir -p "$(dirname "$VENV")" && python -m venv "$VENV"
   "$VENV/Scripts/pip.exe" install -q qqbrowser-skill pymupdf
   # ✅ 用 wrapper，不要直接调 .exe（原因见下）
   bash scripts/qqbrowser_skill_cli.sh version      # 期望 qqbrowser-skill 1.6.3
   bash scripts/setup_env.sh --install              # 建 venv / 装包 / 起守护进程，一步到位
   bash scripts/setup_env.sh                        # 期望全绿
   ```

   🔴 **Windows 真机踩坑（2026-11-12）**：`Scripts/qqbrowser-skill.exe` 是 pip 生成的
   **未签名** launcher，在启用 WDAC / Device Guard 的 Windows 上会被系统策略直接拒绝：
   Git Bash 报 `Permission denied`(126)，`cmd.exe` 报「已被组织 Device Guard 阻止」(199)。
   而 `[ -x ]` 检查完全测不出来 → 自检显示"CLI 就位"，下载链路却全断。
   `scripts/qqbrowser_skill_cli.sh` 用受信任的 `python.exe` 直接驱动
   `x5use.server:main`，参数与输出和 `.exe` 完全一致；`lib_platform.sh` 会自动选它。
   另外 **`pymupdf` 必须装进同一个 venv**：年报内容校验找不到带 pymupdf 的解释器时会
   按"宁缺毋滥"拒收，10 年 PDF 会整段入不了库。

   Windows 常只有 `python.exe` 没有 `python3`；`lib_platform.sh` 会自动把脚本里的 `python3` 调用转发过去，
   **不用手工建别名**。
   `serve --daemon` 还有一道硬前置：**QQ 浏览器必须已安装**（CLI 自身检查，未装直接退出 1），
   且静默安装需要**管理员权限**。装好浏览器后还需在
   **WorkBuddy 设置 → 智能体 → 浏览器操控** 打开开关并安装对应扩展，否则 `Connected clients: 0`。

4. **写凭证**：按本文步骤 5 写 `~/.config/lixinger-download/creds.json`（Git Bash 里即
   `C:/Users/<你>/.config/lixinger-download/creds.json`）。没有凭证就只能依赖浏览器残留登录态。
5. **静态自检**：`bash scripts/selftest.sh`。退出码 0 只说明静态检查过了，**不代表能下载**。
6. **真下载试一次**（只有这一步才知道能不能用）：

   ```bash
   bash scripts/download_company.sh --name 贵州茅台 --market sh --code 600519 \
        --dest "C:/Users/<你>/Desktop/理杏仁验收" --years 10
   ```

   跑完自己盘一下：`年报PDF/` 应有 10 份、`理杏仁财报/` 应有 7 张 CSV；再跑两道验收：

   ```bash
   python scripts/verify_csv_units.py "C:/Users/<你>/Desktop/理杏仁验收/贵州茅台/理杏仁财报/"
   python scripts/audit_annual_pdfs.py "C:/Users/<你>/Desktop/理杏仁验收"
   ```

   跑通了才算这台机器能用；跑不通按 `03-troubleshooting.md` 排查，并请留意：**这条链路从未在 Windows 验证过，
   出问题可能需要改代码，而不是只调环境**。

> 可选：`bash scripts/acceptance_windows.sh --dest "C:/Users/<你>/Desktop/理杏仁验收"` 会把上面几步串起来
> 跑一遍并输出日志，但**这个脚本同样只在 macOS 上验证过逻辑**，不是必需步骤、也不是可用性依据。

### 已知限制

- 整条链路（QQ 浏览器扩展 + 自动登录 + PDF/CSV 落盘 + 两道验收）**未在 Windows 真机跑过**，会遇到什么坑未知。
- `cleanup_downloads.sh --trash` 仅支持 macOS 回收站；其他平台会明确报错退出。
- Chrome/Edge 扩展通道无员工数据，能力边界见 [`05-browser-matrix.md`](05-browser-matrix.md)。
- WSL 跨边界通信未验证。
