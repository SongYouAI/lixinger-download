# 理杏仁内部机制（写脚本/排错时读本文）

> 全部内容来自真机实测（2026-09，macOS + QQ 浏览器 + 长江电力）。

---

## 一、公司页 URL 结构（最关键）

### 标准格式（**四段**，容易写错）

```
https://www.lixinger.com/analytics/company/detail/{market}/{code}/{code}/{tickerId}?{参数}
                                                   ↑        ↑      ↑        ↑
                                                 sh/sz/hk  股票码  重复一次  报表标识
```

⚠️ **常见错误**：
- `/detail/sh600900/600900/bs` → 报错 `exchange must be one of [bj, sh, sz, ...]`（market 段不能带代码）
- `/detail/sh/600900/bs` → 报错 `tickerId must be a number`（**第四段的公司代码不能省**）

✅ **正确示例**：
```
/analytics/company/detail/sh/600900/600900/bs
```

### 关键技巧：日期范围写进 URL（免点按钮）

```
?fs-owner-type=consolidated&start-date=2016-09-16&end-date=2026-09-16
```

| 参数 | 含义 |
|------|------|
| `fs-owner-type=consolidated` | 合并报表（母公司报表用别的字段，默认 consolidated 即可） |
| `start-date` / `end-date` | 时间范围（`YYYY-MM-DD`） |
| `granularity=q` | 季度粒度（部分报表支持 `y` 年度） |

> 💡 日期写进 URL 后，**无需点击页面上的「10 年」按钮**（该按钮文本是 `10 年`，中间带空格，text 定位极易失败）。

### tickerId 映射表

| tickerId | 报表 | 导出文件名特征 |
|----------|------|--------------|
| `bs` | 资产负债表 | `公司_资产负债表_合并报表_{时间戳}.csv` |
| `ps` | 利润表 | `公司_利润表_合并报表_*.csv` |
| `cfs` | 现金流量表 | `公司_现金流量表_合并报表_*.csv` |
| `m` | 财务指标 | `公司_财务指标_合并报表_*.csv` |
| `operation-revenue-constitution` | 营收构成 | `公司_营收构成_*.csv`（年度，无"合并报表"字样） |
| `operating-data` | 经营数据 | `公司_经营数据_*.csv`（季度，40 列） |
| `employee/all-employee` | 员工数据（全体员工） | ⚠️ **UI 导出失效，需 DOM 提取** |

> 获取方式：进入公司任一报表页后，用 JS 读二级导航的 href 即可拿到全量映射（见下方速查）。

---

## 二、导出流程（通用三连）

```bash
CLI=~/.workbuddy/binaries/python/envs/qqbrowser-ctl/bin/qqbrowser-skill
SID=lixinger-dl    # 会话 ID

# 1) 打开导出菜单
"$CLI" browser_find_and_act --sessionId $SID --by text --value "导出CSV" --action click
"$CLI" browser_wait --sessionId $SID --seconds 2 > /dev/null

# 2) 【关键】弹窗 index 每次都变，必须重新快照动态获取
"$CLI" browser_snapshot --sessionId $SID > /tmp/pop.txt
I1=$(grep -oE '\[[0-9]+_[a-z0-9_]+\]<input 壹' /tmp/pop.txt | grep -oE '[0-9]+_[a-z0-9_]+' | head -1)
I2=$(grep -oE '\[[0-9]+_[a-z0-9_]+\]<a 时间横排 - 降序' /tmp/pop.txt | grep -oE '[0-9]+_[a-z0-9_]+' | head -1)

# 3) 先选单位「壹」，再点排序「时间横排 - 降序」→ 触发下载
"$CLI" browser_click_element --sessionId $SID --index "$I1"
"$CLI" browser_wait --sessionId $SID --seconds 1 > /dev/null
"$CLI" browser_click_element --sessionId $SID --index "$I2"
"$CLI" browser_wait --sessionId $SID --seconds 5 > /dev/null
```

> ⚠️ 排序选项文字是「时间**横**排」（不是"模排"），低分辨率截图易误读。
> ⚠️ 单位「壹」的 index 在不同报表页不同（实测 330/299/260/272/183/198…），**每次必须重新取**。

### 导出文件特征

- 下载到浏览器默认下载目录（macOS：`~/Downloads/`）
- 编码 UTF-8 **带 BOM**（Excel 打开中文正常）
- 首行：`财报类型,股票代码,股票名称,{日期列...}`
- 第二行日期列降序（如 `2026-06-30 → 2016-09-30`）
- 第三行货币单位（壹 → `元`）

---

## 三、各页面差异（避坑要点）

| 报表 | 单位选项 | 导出按钮 | 特殊说明 |
|------|:---:|:---:|------|
| bs / ps / cfs / m | ✅ 有（壹/万/百万/亿） | 工具栏单个 | 标准流程 |
| 营收构成 | ✅ 有 | 单个 | 年度粒度，URL 带 `unit=hundred_million` |
| 经营数据 | ✅ 有（弹窗**无「壹」单位项**，直接点排序即导出） | 单个 | 季度，40 列 |
| **员工数据** | ❌ **无单位行**（单位固定"人"） | **两个导出按钮** | ⚠️ **UI 导出在自动化下不触发下载** |

### 员工数据处理（DOM 提取兜底）

```bash
# 1) 提取表格（第 2 个 table 是主表：19 行 × 10 年）
"$CLI" browser_eval_content_js --sessionId $SID \
  --script "JSON.stringify(Array.from(document.querySelectorAll('table')[1].querySelectorAll('tr')).map(tr=>Array.from(tr.querySelectorAll('td,th')).map(td=>td.innerText.trim())))" \
  > /tmp/emp_table_raw.txt

# 2) 本地转 CSV（Python 处理，取"原值"列、跳过"同比"列）
python3 - <<'PY'
import json, csv
raw = open('/tmp/emp_table_raw.txt').read()
obj = json.loads(raw[raw.find('{'):raw.rfind('}')+1])
data = json.loads(obj['text'])
years = data[0][1:]
rows = [[r[0]] + [r[1+i*2].replace(',','') if 1+i*2 < len(r) else '' for i in range(len(years))]
        for r in data[2:] if r and r[0]]
with open('输出路径.csv','w',newline='',encoding='utf-8-sig') as f:
    w = csv.writer(f); w.writerow(['指标']+years); w.writerows(rows)
PY
```

> 表格结构：`行0=年份表头`、`行1=原值/同比`、`行2+=指标数据`（每年占 2 列：原值 + 同比）。
> 实测可提取 17 个指标：人均营业总收入、人均净利润、人均薪酬、员工人数、博士/硕士/学士/大专/高中及以下人数、生产/销售/技术/财务/行政/其他人员人数。

---

## 四、年报 PDF 下载

### 链接位置（重要：在「公告」筛选页，不在员工页）

⚠️ **年报链接不在员工页/经营数据页快照**。那些页底部只有临时公告（如"发电量完成情况公告"），**没有**年度报告。

✅ **正确位置**：公司「公告」页 + `search-key` 筛选年度报告：
```
{BASE}/{market}/{code}/{code}/announcement?search-key=年度报告
```
中文 `年度报告` 需 URL 编码：`%E5%B9%B4%E5%BA%A6%E6%8A%A5%E5%91%8A`。

快照中精确匹配 `{公司名}{YYYY}年年度报告/>points to a pdf`（**必须排除**"摘要""半年度"等噪音）：
```
[322_7ysb_xlwt]<a 长江电力2025年年度报告/>points to a pdf.
```
> 默认列表只懒加载最近几条，需 `browser_scroll_to_bottom` 兜底；筛选后通常一次出齐（2015–2025 共 11 份），按 `YEARS` 过滤取起点年份起的 10 年。

### 下载命令

```bash
"$CLI" browser_download_file --sessionId $SID --index "186_956k_b0pi"
"$CLI" browser_wait --sessionId $SID --seconds 6 > /dev/null
```

> ⚠️ CLI 会返回 `Failed! This is not a download button!` —— **这是误报**，实际下载已触发，去下载目录确认即可。

### 必须重命名

理杏仁原始文件名完全不可读：`600900_20260430_WC8R.pdf`
→ 下载后**必须**重命名为：`{公司}_{YYYY}年年度报告.pdf`

推荐做法：下载前记录下载目录快照，下载后取差集拿到新文件，立即重命名（见主脚本实现）。

---

## 五、搜索公司（获取 market / code）

理杏仁搜索框是 **vue-multiselect** 组件，常规输入无效，需用 JS：

```bash
# 1) 点击搜索框（首页顶部）
"$CLI" browser_click_element --sessionId $SID --index "<搜索框index>"

# 2) 【关键】用 native setter 触发 Vue 的响应式（普通 input_text 无效）
"$CLI" browser_eval_content_js --sessionId $SID --script \
"(function(){const i=document.querySelector('input[placeholder*=\"搜索\"]');
const s=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
s.call(i,'长江电力');i.dispatchEvent(new Event('input',{bubbles:true}));i.focus();return 'ok';})()"

# 3) 【关键】vue-multiselect 监听 mousedown（不是 click），且 handler 在 .multiselect__option 内层
"$CLI" browser_eval_content_js --sessionId $SID --script \
"(function(){const o=Array.from(document.querySelectorAll('.multiselect__element'))
 .find(e=>e.textContent.includes('长江电力'));
const inner=o.querySelector('.multiselect__option')||o;
[new MouseEvent('mousedown',{bubbles:true}),new MouseEvent('mouseup',{bubbles:true}),
 new MouseEvent('click',{bubbles:true,cancelable:true})].forEach(e=>inner.dispatchEvent(e));return 'ok';})()"

# 4) 跳转后读取真实 URL，即可解析出 market / code
"$CLI" browser_eval_content_js --sessionId $SID --script "JSON.stringify({url:location.href})"
```

> 💡 其实**不必每家都搜索**：知道股票代码即可直接拼 URL（如茅台 `sh` + `600519`）。
> 只有在不知道代码时才需要走搜索流程。

---

## 六、会话管理（稳定性关键）

```bash
# ✅ 推荐：隔离会话（稳定，导航不会释放）
"$CLI" browser_start_session --sessionId lixinger-dl --title "理杏仁下载" --color green \
  --initialUrl "https://www.lixinger.com/analytics/company/detail/sh/600900/600900/bs"

# ❌ 避免：attach 用户已开的 tab —— 页面导航后 session 会被释放，后续命令全部报
#    "Session does not exist or has been released"
"$CLI" browser_end_session --sessionId lixinger-dl    # 结束时调用
```

---

## 七、完整命令速查

```bash
CLI=~/.workbuddy/binaries/python/envs/qqbrowser-ctl/bin/qqbrowser-skill
SID=lixinger-dl

"$CLI" status                                                    # 守护进程状态
"$CLI" browser_tab_list                                          # 标签页列表
"$CLI" browser_start_session --sessionId $SID --initialUrl <url> # 开会话
"$CLI" browser_go_to_url     --sessionId $SID --url <url>        # 导航
"$CLI" browser_wait          --sessionId $SID --seconds 5        # 等待
"$CLI" browser_snapshot      --sessionId $SID                    # 快照（带元素 index）
"$CLI" browser_find_and_act  --sessionId $SID --by text --value "导出CSV" --action click
"$CLI" browser_click_element --sessionId $SID --index "<index>"  # 点元素
"$CLI" browser_eval_content_js --sessionId $SID --script "<js>"  # 执行 JS
"$CLI" browser_download_file --sessionId $SID --index "<index>"  # 触发下载
"$CLI" browser_end_session   --sessionId $SID                    # 关会话
```

---

## 八、归档（跨盘注意）

```bash
# ❌ mv 在跨设备（如内置盘 → 外置盘）会报：EXDEV: cross-device link not permitted
# ✅ 用 cp + rm
cp "$HOME/Downloads/xxx.csv" "$DEST/" && rm "$HOME/Downloads/xxx.csv"
```
