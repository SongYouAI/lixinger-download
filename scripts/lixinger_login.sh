#!/usr/bin/env bash
# 理杏仁自动登录（QQ 浏览器 / qqbrowser-skill 通道）
#
# 为什么单独做：以前 QQ 浏览器全靠人肉扫码/输密码，跑批量前得手工登一次，过期就整批失败。
#   实测 2026-11-10：理杏仁登录弹窗**没有验证码**，账号+密码即可登，可以全自动。
#
# 做法：
#   1. 读 ~/.config/lixinger-download/creds.json（600 权限，已 gitignore）
#   2. 以理杏仁首页开全新会话
#   3. 已是登录态 → 直接退出 0
#   4. 否则点「开始使用 / 登录/注册」开弹窗 → 用 JS 派发 React input 事件写账号密码 → 点「登录」
#   5. 等 6s 复查登录态，通过退出 0，失败退出 1
#
# 用法:
#   bash lixinger_login.sh            # 自动登录（已登录则秒退）
#   bash lixinger_login.sh --check    # 只查登录态
#   bash lixinger_login.sh --keep     # 登录后不关会话（后续命令可复用这个 SID，脚本会打印它）
#
# 退出码: 0=已登录, 1=登录失败, 2=凭证缺失/环境问题
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib_platform.sh"
CREDS="$LX_CREDS"
CLI="$LX_CLI"

MODE="login"
[ "${1:-}" = "--check" ] && MODE="check"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

if [ ! -x "$CLI" ]; then
  echo "❌ 找不到 qqbrowser-skill: $CLI"; exit 2
fi
if [ ! -f "$CREDS" ]; then
  echo "❌ 缺凭证文件: $CREDS"
  echo "   建法: mkdir -p ~/.config/lixinger-download && 写入 {\"account\":\"手机号\",\"password\":\"密码\"} 并 chmod 600"
  exit 2
fi
CREDS_PY="$(lx_native_path "$CREDS")"
ACC=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['account'])" "$CREDS_PY" 2>/dev/null)
PWD_=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['password'])" "$CREDS_PY" 2>/dev/null)
if [ -z "$ACC" ] || [ -z "$PWD_" ]; then
  echo "❌ 凭证文件里 account / password 不完整"; exit 2
fi

# 端口 8765 的守护进程没起来就先拉起来
if ! "$CLI" status 2>&1 | grep -q "Daemon is running"; then
  echo "  → 启动浏览器守护进程…"
  "$CLI" serve --daemon >/dev/null 2>&1
  sleep 3
fi

SID="lx-login-$(date +%s)"
cleanup() {
  if [ "$KEEP" -eq 0 ]; then "$CLI" browser_end_session --sessionId "$SID" >/dev/null 2>&1; fi
}
trap cleanup EXIT

js() {  # $1=js ; 输出原始返回
  "$CLI" browser_eval_content_js --sessionId "$SID" --script "$1" 2>&1
}

# 登录态判定：页面文本里出现账号（手机号）即视为已登录。
# 不用「登录/注册」是否存在来判 —— 那个链接在已登录状态下也可能残留。
LOGIN_JS="(()=>{var t=document.body.innerText;var a='${ACC}';if(t.indexOf(a)>=0)return 'STATE=IN';if(/登录\\/注册|开始使用/.test(t))return 'STATE=OUT';return 'STATE=UNK';})()"
state() { js "$LOGIN_JS" | grep -oE 'STATE=[A-Z]+' | head -1 | cut -d= -f2; }

# 🔴 就绪等待（2026-11-10 两次踩坑）：理杏仁是 SPA。
#   坑1: start_session 后 6s 页面常是 about:blank → 固定等待会得 UNK。
#   坑2: 仅判「body 文本 >200 字」不够 —— 300 字的骨架/半渲染态会返回 UNK，
#        紧接着去找登录弹窗必然 OPENED=none / FILL=noinput（回归 3 实测）。
#   坑3: 1566 字的中间态会短暂渲染出「登录/注册」→ 判 OUT，随后才变成 11846 字 IN
#        （2026-11-11 验收脚本实测：第 3 项误报未登录，但后续下载自动登录成功）。
#   正解: IN 立即放行；OUT 必须等满超时、确认稳定才认；UNK 一律继续等。
wait_ready() {  # $1=最多迭代几次（每次约 2s）
  local i n=0 t s last=""
  for i in $(seq 1 "$1"); do
    t=$(js "document.body.innerText.length" | grep -oE '[0-9]+' | head -1)
    if [ -n "$t" ] && [ "$t" -gt 200 ] 2>/dev/null; then
      s=$(state)
      if [ "$s" = "IN" ]; then
        echo "  ⏱️  页面就绪(${i}s, 文本 ${t} 字, 状态 IN)"; return 0
      fi
      last="$s"
    fi
    "$CLI" browser_wait --sessionId "$SID" --seconds 2 >/dev/null 2>&1
    n=$((n+2))
  done
  if [ "$last" = "OUT" ]; then
    echo "  ⏱️  等待 ${n}s 后状态稳定为 OUT(文本 ${t:-0} 字)"; return 0
  fi
  echo "  ⏱️  等待 ${n}s 状态仍为 UNK(文本 ${t:-0} 字)"
  return 1
}

echo "── 理杏仁登录检查 ──"
echo "  账号: ${ACC:0:3}****${ACC: -4}"
"$CLI" browser_start_session --sessionId "$SID" --title "理杏仁登录" --color cyan \
  --initialUrl "https://www.lixinger.com/" >/dev/null 2>&1
"$CLI" browser_wait --sessionId "$SID" --seconds 4 >/dev/null 2>&1
# 会话刚建时导航常没完成（about:blank）→ 补一次显式导航，失败也不算错（页面可能已进入）
U=$("$CLI" browser_eval_content_js --sessionId "$SID" --script "location.href" 2>/dev/null | grep -oE 'https?://[^"]+' | head -1)
case "$U" in
  *lixinger.com*) : ;;
  *) "$CLI" browser_go_to_url --sessionId "$SID" --url "https://www.lixinger.com/" >/dev/null 2>&1 ;;
esac
wait_ready 15 || true
ST=$(state)
# UNK = 页面没渲染完整，此时找弹窗必然失败。重载一次再等；仍 UNK 就明确报错，不猜。
if [ "$ST" = "UNK" ]; then
  echo "  → 页面未渲染完整，重载后重试一次…"
  "$CLI" browser_go_to_url --sessionId "$SID" --url "https://www.lixinger.com/" >/dev/null 2>&1
  "$CLI" browser_wait --sessionId "$SID" --seconds 3 >/dev/null 2>&1
  wait_ready 15 || true
  ST=$(state)
fi
echo "  当前状态: ${ST:-未知}"
if [ "$ST" = "UNK" ]; then
  echo "❌ 页面始终未渲染完整，无法判定登录态（检查网络 / 站点状态后重跑）"
  exit 1
fi

if [ "$MODE" = "check" ]; then
  [ "$ST" = "IN" ] && { echo "✅ 已登录"; exit 0; }
  echo "⚠️ 未登录"; exit 1
fi

if [ "$ST" = "IN" ]; then
  echo "✅ 已是登录态，无需登录"
  [ "$KEEP" -eq 1 ] && echo "SID=$SID"
  exit 0
fi

# 1) 打开登录弹窗（首页按钮叫「开始使用」，其他页是「登录/注册」）
OPEN_JS="(()=>{var els=[].slice.call(document.querySelectorAll('button,a'));for(var i=0;i<els.length;i++){var t=(els[i].innerText||'').trim();if(t==='开始使用'||t==='登录/注册'){els[i].click();return 'OPENED='+t;}}return 'OPENED=none';})()"
echo "  → 打开登录弹窗: $(js "$OPEN_JS" | grep -oE 'OPENED=[^"]*' | head -1)"
"$CLI" browser_wait --sessionId "$SID" --seconds 3 >/dev/null 2>&1

# 2) 写账号密码
#    必须用 HTMLInputElement.prototype 的 value setter + 派发 input 事件，
#    直接 el.value= 赋值 React 收不到（受控组件不会更新 state）。
#    这样也顺手绕过「旧账号自动填充残留」——直接覆盖成新值。
FILL_JS="(()=>{
  var acc='${ACC}', pwd='${PWD_}';
  var setter=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
  var ai=document.querySelector('input[placeholder=\"账号或手机号\"]');
  var pi=document.querySelector('input[placeholder=\"密码\"]');
  if(!ai||!pi) return 'FILL=noinput';
  ai.focus(); setter.call(ai,acc); ai.dispatchEvent(new Event('input',{bubbles:true}));
  pi.focus(); setter.call(pi,pwd); pi.dispatchEvent(new Event('input',{bubbles:true}));
  return 'FILL=ok:'+(ai.value===acc?'acc_ok':'acc_bad')+':'+(pi.value.length===pwd.length?'pwd_ok':'pwd_bad');
})()"
FILL_RES=$(js "$FILL_JS" | grep -oE 'FILL=[^"]*' | head -1)
echo "  → 写入表单: $FILL_RES"
case "$FILL_RES" in
  FILL=ok:acc_ok:pwd_ok) ;;
  *) echo "❌ 表单写入失败（弹窗没出来 / 选择器变了）"; exit 1 ;;
esac

# 3) 点「登录」（type=submit 的那个）
SUB_JS="(()=>{var bs=[].slice.call(document.querySelectorAll('button'));for(var i=0;i<bs.length;i++){var b=bs[i];if(b.type==='submit'&&(b.innerText||'').trim()==='登录'){b.click();return 'SUB=clicked';}}return 'SUB=none';})()"
echo "  → 提交: $(js "$SUB_JS" | grep -oE 'SUB=[^"]*' | head -1)"

# 4) 等待并复查
"$CLI" browser_wait --sessionId "$SID" --seconds 6 >/dev/null 2>&1
ST2=$(state)
if [ "$ST2" = "IN" ]; then
  echo "✅ 登录成功"
  [ "$KEEP" -eq 1 ] && echo "SID=$SID"
  exit 0
fi
echo "❌ 登录失败（状态: ${ST2:-未知}）"
echo "   可能原因: 账号密码错 / 账号到期 / 站点加了验证码 / 弹窗结构变了"
echo "   排查: bash $SCRIPT_DIR/lixinger_login.sh --check   # 再跑一次看状态"
exit 1
