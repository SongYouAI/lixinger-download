# 故障排查（报错时读本文）

> 按现象查表。每条都标注了**根因**，不要只看报错就乱猜。

---

## 一、环境与连接

| 现象 | 根因 | 解决 |
|------|------|------|
| `command not found: qqbrowser-skill` | 技能商店只装了说明书，CLI 本体未装 / 未用绝对路径 | 用 `$VENV/bin/qqbrowser-skill`；未装则 `pip install qqbrowser-skill` |
| `Session "xxx" does not exist or has been released` | **attach 了用户 tab，导航后会话被释放** | 改用 `browser_start_session` 开隔离会话 |
| `Connected clients: 0` | 浏览器未连上守护进程 | 关闭浏览器重开，或重新 `serve --daemon` |
| 守护进程起不来 | 端口 8765 / 8766 被占用 | 检查占用进程，或重启浏览器后重试 |
| `invalid choice: 'get_tab_content'` | 命令不存在（说明书已过时） | 用 `browser_snapshot` 替代 |

---

## 二、页面与 URL

| 现象 | 根因 | 解决 |
|------|------|------|
| 页面显示「加载数据失败」+ `exchange must be one of [bj, sh, sz...]` | URL 第一段写成了 `sh600900` | 第一段必须是纯市场码 `sh` / `sz` / `hk` |
| `tickerId must be a number` | URL 只有三段，漏了重复的公司代码 | 必须是四段：`/sh/600900/600900/bs` |
| 页面跳回个人中心 | 已登录用户访问 `www.lixinger.com` 会重定向 | 正常现象，直接导航到报表 URL 即可 |
| 导出的数据只有 5 年 | 没设置时间范围（默认 5 年） | URL 加 `start-date` / `end-date`（10 年前 ~ 今天） |

---

## 三、交互与定位

| 现象 | 根因 | 解决 |
|------|------|------|
| `No element found with locator by=text, value=10年` | 按钮文本是 `10 年`（**数字与"年"之间有空格**） | 用 URL 日期参数绕过，不必点按钮 |
| 搜索框输入后无反应 | 理杏仁是 Vue 应用，程序化赋值不触发 `onChange` | 用 native setter + `input` 事件（见 internals 文档第五节） |
| 点搜索结果不跳转 | vue-multiselect 监听 **mousedown**，且 handler 绑定在 `.multiselect__option`（li 的**内层**） | 对内层元素派发 `mousedown → mouseup → click` 完整序列 |
| 点了「壹」没反应 | **弹窗 index 每次都变**（实测 330/299/260/272/183/198） | 每次导出前重新 `browser_snapshot` 动态取 index |
| 排序选项找不到 | 文字是「时间**横**排」不是"模排"（低分辨率截图易误读） | 按 `时间横排 - 降序` 精确匹配 |

---

## 四、下载与文件

| 现象 | 根因 | 解决 |
|------|------|------|
| `Failed! This is not a download button!` | **CLI 误报**，下载实际已触发 | 忽略报错，去下载目录确认文件 |
| PDF 下载了但名字是 `600900_20260430_WC8R.pdf` | 理杏仁原始名不可读 | 下载后立即重命名为 `{公司}_{YYYY}年年度报告.pdf` |
| 员工数据点了导出但没文件 | 该页 UI 导出在自动化下不触发（已知限制） | 用 DOM 提取表格 + 本地生成 CSV（见 internals 第三节） |
| `mv: EXDEV: cross-device link not permitted` | 跨设备移动（内置盘 → 外置盘） | 用 `cp` + `rm` 代替 `mv` |
| 下载目录找不到新文件 | 下载未完成（`.crdownload` 暂存中） | 增加等待时间；确认 `.crdownload` 是否已转为正式文件 |

---

## 五、排查决策树

```
导出失败
├─ 页面白屏 / "加载数据失败"
│   └─ URL 格式错 → 检查四段结构（/sh/600900/600900/bs）
├─ 能打开页面，但点导出没反应
│   ├─ 会话已释放？ → 用 start_session 重开
│   ├─ index 过期？ → 重新 snapshot 取 index
│   └─ 是员工页？   → 走 DOM 提取兜底
├─ 点了但没下载文件
│   ├─ 等待时间不够？ → 增加到 8-10 秒
│   ├─ 是否误报？     → 检查下载目录（CLI 常报 "not a download button" 但已下载）
│   └─ 登录态过期？   → 页面跳回登录页，需手动重登
└─ 数据不对（年份数不对）
    └─ URL 没带 start-date/end-date → 补上日期参数
```

---

## 六、登录后失效的处理

理杏仁 token 会过期。若出现以下任一情况，**手动登录一次**即可恢复：

- 页面自动跳回登录页
- 快照中出现"登录"按钮（而非账号/手机号）
- 导出突然全部失败

```bash
# 手动登录后验证：
"$CLI" browser_go_to_url --sessionId $SID --url "https://www.lixinger.com"
"$CLI" browser_eval_content_js --sessionId $SID --script "JSON.stringify({url:location.href})"
# 期望：url 为 /profile/center/... （已登录）而非登录页
```
