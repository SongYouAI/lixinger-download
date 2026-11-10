# 05 · 三浏览器矩阵：能力边界、登录、下载

> 2026-11-10 **在 macOS 上**实测。目的：同一个 skill 在 **Chrome / Edge / QQ 浏览器**上都能把内容下下来，且**不需要手工登录**。Windows 上的三浏览器通道未测试。

---

## 一、先搞清楚：三个浏览器走的是两条完全不同的通道

| 浏览器 | 通道 | 谁在驱动 | 能否执行 JS | 下载方式 |
|---|---|---|---|---|
| **QQ 浏览器** | `qqbrowser-skill` CLI | `scripts/*.sh` 直接调 | ✅ `browser_eval_content_js` | `browser_click_element` 点链接 |
| **Chrome** | WorkBuddy 扩展 | **只能 agent 用 `mcp__browser__*` 工具驱动**（脚本调不到 MCP） | ❌ | 浏览器自身下载 |
| **Edge** | WorkBuddy 扩展 | 同上 | ❌ | 浏览器自身下载 |

**这条区别决定一切**：
- QQ 的活可以写成 shell 脚本，能定时跑、能批量。
- Chrome / Edge **没有可调用的 CLI**，`mcp__browser__*` 只存在于 agent 会话里 → 只能由 agent 按本文档的步骤驱动，**不能进 `batch_download.sh`**。

> 也正因为如此，Chrome/Edge 这条路**能做什么、不能做什么**要提前讲清楚，别承诺做不到的事（见第五节）。

---

## 二、一次性准备：让 Chrome / Edge 愿意自动下载

```bash
bash scripts/setup_browser_downloads.sh --check   # 先看现状
bash scripts/setup_browser_downloads.sh           # 改（会自动退出浏览器）
bash scripts/setup_browser_downloads.sh --revert  # 一键还原
```

改两项（每个 Profile）：

| 偏好项 | 原值 | 改成 | 不改会怎样 |
|---|---|---|---|
| `download.prompt_for_download` | `true` | `false` | 每次下载弹 macOS 原生「存储为」对话框，**扩展点不掉 → 文件永远不落盘**（实测点三次全无反应） |
| `plugins.always_open_pdf_externally` | 未设 | `true` | 点年报 PDF 只**在线预览**（实测能正常显示 323 页），不下载 |

**必须浏览器完全退出后再改**，否则 Chrome 退出时会把内存里的旧配置回写覆盖。
`osascript ... quit` 常被「自动化」权限静默拦掉 → 脚本会自动退回 `killall -TERM`（Chrome/Edge 收到 TERM 会正常收尾，不会损坏配置）。

改完重新打开浏览器，**登录 Cookie 不受影响**。

---

## 三、自动登录（三浏览器都已验证）

凭证统一放 `~/.config/lixinger-download/creds.json`（`chmod 600`，已在 `.gitignore`）：

```json
{ "account": "手机号", "password": "密码" }
```

> 🔴 仓库是 **GitHub public**，凭证文件永远不许提交。换号只改这一个文件。
> 登录页实测**没有验证码**，账号+密码可直接登。

### 3.1 QQ 浏览器：一条命令

```bash
bash scripts/lixinger_login.sh          # 已登录则秒退；未登录自动填表提交
bash scripts/lixinger_login.sh --check  # 只查状态
bash scripts/lixinger_login.sh --keep   # 登录后保留会话并打印 SID
```

实现要点（踩过的坑都写进脚本了）：

- **不能用 `el.value = x` 赋值**。输入框是 React 受控组件，直接赋值 React 收不到，点登录会报「请输入账号」。
  必须 `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el, v)` + `dispatchEvent(new Event('input',{bubbles:true}))`。
- **必须等页面就绪再判定**。`browser_start_session` 之后 6 秒，页面常常还是 `about:blank`，
  此时 `innerText` 为空 → 判定得到 `UNK` → 脚本会去找根本不存在的按钮（实测第一版就栽在这）。
  现在改为轮询 `document.body.innerText.length > 200`（实测 1 秒就绪）。
- **登录态判据**：页面文本里出现账号（手机号）即算已登录；不要用「登录/注册」链接是否存在来判断，已登录时它也可能残留。
- 会话刚建时导航可能没完成 → 脚本会补一次 `browser_go_to_url`。

### 3.2 Chrome / Edge：agent 按序调用（无脚本）

```
1) mcp__browser__browsers_list            ← 必须每次重取！浏览器重启后 id 会变
                                            实测：Chrome 4→5、Edge 3→6
2) mcp__browser__user_open_tabs(browser)  ← 若返回空，先 open -a "Google Chrome" 打开窗口
3) mcp__browser__tabs_claim(browser, tab)
4) mcp__browser__dom_cua_get_visible_dom  ← 找「开始使用」按钮 / 「登录/注册」链接
5) mcp__browser__dom_cua_click(node)      ← 打开登录弹窗
6) dom_cua_get_visible_dom                ← 重新取快照（node_id 每次快照都会变！）
7) dom_cua_click(账号框) → dom_cua_type("手机号")
8) dom_cua_get_visible_dom                ← ⚠️ 输入后必须重取，否则下一步报 stale
9) dom_cua_click(密码框) → dom_cua_type("密码")
10) dom_cua_click(登录按钮：type=submit 且文本「登录」)
11) 等 6~8s → tab_url 含 /profile/center 即成功
```

登录弹窗的稳定选择器（两浏览器一致）：

| 元素 | 选择器 |
|---|---|
| 账号框 | `input[placeholder="账号或手机号"]` |
| 密码框 | `input[placeholder="密码"]` |
| 提交 | `button[type=submit]`，文本 `登录` |

**坑清单**
- 输入后不重取 DOM → `DOM node_id is stale`。
- `tabs_new(url=...)` 有时建出**空标签**（title/url 皆空，后续 `tab_url` 报 `url must be absolute`）→ 改用 `user_open_tabs` + `tabs_claim`，或再 `tab_goto` 一次。
- 截图偶尔停在**深色 loading 屏**，不代表失败，等 10s 再读 DOM。
- 账号框可能带着**上次的自动填充残留**（实测 Chrome 里残留的是旧手机号，此处不记录具体号码）→ 先 `dom_cua_click` + `Meta+a` + `Backspace` 清空再输入。

---

## 四、取数据（ext 通道，Chrome/Edge）

### 4.1 年报 PDF：比 QQ 那条路简单得多

`/analytics/company/detail/{market}/{code}/{code}/bs` 这一页的 DOM 里**直接带 10 年年报直链**：

```html
<a href="https://static.sse.com.cn/.../600795_20260415_9PNY.pdf"
   title="国电电力2025年年度报告(于2026-04-15公告)" />
```

→ **不用进公告页、不用翻页、不用管索引跨页失效**（那三个坑是 QQ 路径的历史包袱）。
做法：读一次 DOM，按 `title` 里的 `YYYY年年度报告` 取年份 → 对每个 href 调 `tab_goto` → 文件落 `~/Downloads`。

> href 是交易所公开直链，**不需要 cookie/token**；但 `static.sse.com.cn` 有 `acw_sc__v2` JS 挑战，
> **curl 直下只会拿到 3872B 挑战页**，必须由浏览器发起。

### 4.2 CSV：没有「单位」选项，默认就是元

点 `导出CSV` → 弹出 4 个排序项 → 点「时间横排 - 降序」→ 直接落盘。

| 项 | 实测结果 |
|---|---|
| 下拉选项 | 只有排序：时间横排-降序 / 时间横排-升序 / 时间竖排-降序 / 时间竖排-升序 |
| 单位选择 | **没有**。和 QQ 路径不同，**不需要点「壹」** |
| 导出单位 | **元**（`verify_csv_units.py` 判 `✓元`） |
| 文件名 | `{公司}_{表名}_合并报表_{YYYYMMDD_HHMMSS}.csv` |

> 页面左上角显示的「默认单位: 亿元」只影响**网页展示**，不影响 CSV 导出。

---

## 五、能力边界（别承诺做不到的事）

| 能力 | QQ 浏览器 | Chrome / Edge |
|---|---|---|
| 年报 PDF | ✅ | ✅ |
| 6 类财报 CSV | ✅ | ✅（实测资产负债表通过，其余同理） |
| **员工数据（17 指标 × 10 年）** | ✅ DOM 提取 + 本地生成 CSV | ❌ **未实现**。该表靠 JS 遍历单元格，ext 通道无 JS 执行能力，只能从 DOM 快照解析文本，尚未做 |
| 单位校验 / PDF 内容审计 | ✅ | ✅ 同一套 Python 脚本，与浏览器无关 |
| 批量 / 定时 | ✅ `batch_download.sh` | ❌ 无法进脚本，只能由 agent 逐家跑 |

> 结论：**Chrome/Edge 覆盖 PDF + 6 类 CSV；员工数据目前只有 QQ 通道能给。**
> 要补齐，得在 ext 通道上加「DOM 快照解析表格」的实现，属后续工作。

---

## 六、验收记录（2026-11-10 国电电力 sh600795）

| 浏览器 | 自动登录 | PDF | CSV | 备注 |
|---|---|---|---|---|
| Chrome | ✅ | ✅ 2025(1881101B) / 2016(4072739B)，**与 cninfo 官方件字节一致** | ✅ 资产负债表，`✓元` | |
| Edge | ✅ | ✅ 2017(3908054B) | 未测（同一站点逻辑，prefs 已改） | |
| QQ | ✅ 登录态检测通过（页面文本含账号） | ✅（旧脚本，10 年） | ✅（旧脚本，6 张） | 登录填表路径未做「登出→重登」实测 |

**改配置前后的对照**：改之前，Chrome 里点 PDF 链接、点阅读器下载按钮、Option+点击，**三种方式全都不落盘**；
改之后 `tab_goto` 直链即静默下载。差异全部来自那两个偏好项。
