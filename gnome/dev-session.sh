#!/usr/bin/env bash
# 启动一个隔离的嵌套 GNOME Shell 开发会话（GNOME 50 的 --devkit）。
#
# 会在当前桌面上开一个小窗口，里面是独立的 Shell。关闭窗口即退出，
# 不会改动当前登录会话的扩展和设置。
#
#   ./dev-session.sh              # 本地桩服务，显示 ¥110.00
#   USE_STUB=0 ./dev-session.sh   # 不启桩服务，在设置里填真实 API Key
#
# 依赖：mutter-devkit（GNOME 49+ 靠它把嵌套 Shell 显示成窗口）。
set -euo pipefail

cd "$(dirname "$0")"

UUID=deepseek-balance-indicator@hungtcs.dev
DEV_DIR="$(pwd)/dist/dev/$UUID"
USE_STUB="${USE_STUB:-1}"
STATE_DIR="${DEEPSEEK_DEV_STATE:-${XDG_RUNTIME_DIR:-/tmp}/deepseek-dev-session}"

if ! command -v mutter-devkit >/dev/null 2>&1 &&
   ! [ -x /usr/libexec/mutter-devkit ]; then
    echo "缺少 mutter-devkit。Fedora：sudo dnf install mutter-devkit" >&2
    exit 1
fi

# 多个实例会同时弹出多个窗口，按 exe 精确判定，避免 pkill -f 匹配到脚本自己。
for pid in $(pgrep -x gnome-shell 2>/dev/null); do
    if grep -qa devkit "/proc/$pid/cmdline" 2>/dev/null; then
        echo "已有嵌套会话在运行（pid=$pid）。先停掉：kill $pid" >&2
        exit 1
    fi
done

echo "→ 构建开发包"
make -s dev-bundle

rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR/config" "$STATE_DIR/data/gnome-shell/extensions"

# 宿主 ~/.local/share 下的字体、图标和其他扩展照常可见，只有 gnome-shell
# 这一层换成临时目录，保证开发中的扩展不会出现在真实会话里。
shopt -s nullglob
for entry in "$HOME/.local/share"/*; do
    [ "$(basename "$entry")" = gnome-shell ] && continue
    ln -sfn "$entry" "$STATE_DIR/data/$(basename "$entry")"
done
for entry in "$HOME/.local/share/gnome-shell"/*; do
    [ "$(basename "$entry")" = extensions ] && continue
    ln -sfn "$entry" "$STATE_DIR/data/gnome-shell/$(basename "$entry")"
done
for entry in "$HOME/.local/share/gnome-shell/extensions"/*; do
    ln -sfn "$entry" "$STATE_DIR/data/gnome-shell/extensions/$(basename "$entry")"
done
shopt -u nullglob
ln -sfn "$DEV_DIR" "$STATE_DIR/data/gnome-shell/extensions/$UUID"

export XDG_CONFIG_HOME="$STATE_DIR/config"
export XDG_DATA_HOME="$STATE_DIR/data"
# XDG_RUNTIME_DIR 和 WAYLAND_DISPLAY 保持宿主值：mutter-devkit 必须在
# 当前桌面开窗口。私有 D-Bus 会话由 dbus-run-session 提供。

STUB_PID=""
cleanup() {
    if [ -n "$STUB_PID" ]; then
        kill "$STUB_PID" 2>/dev/null || true
    fi
    chmod -R u+rwX "$STATE_DIR" 2>/dev/null || true
    rm -rf "$STATE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

if [ "$USE_STUB" = 1 ]; then
    PORT=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
)
    python3 -u - "$PORT" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

BODY = json.dumps({
    'is_available': True,
    'balance_infos': [{
        'currency': 'CNY',
        'total_balance': '110.00',
        'granted_balance': '10.00',
        'topped_up_balance': '100.00',
    }],
}).encode()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *args):
        pass

HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
PY
    STUB_PID=$!
    export DEEPSEEK_BALANCE_ENDPOINT="http://127.0.0.1:$PORT/user/balance"

    ready=0
    for _ in $(seq 1 50); do
        if curl -fsS -o /dev/null "$DEEPSEEK_BALANCE_ENDPOINT" 2>/dev/null; then
            ready=1
            break
        fi
        sleep 0.1
    done
    if [ "$ready" != 1 ]; then
        echo "桩服务没有启动成功" >&2
        exit 1
    fi
    echo "→ 桩服务 $DEEPSEEK_BALANCE_ENDPOINT"
else
    unset DEEPSEEK_BALANCE_ENDPOINT || true
    echo "→ 未启用桩服务，请在设置里填写真实 API Key"
fi

SHELL_VERSION=$(gnome-shell --version | awk '{print $3}')

echo "→ 启动嵌套 GNOME Shell（关闭窗口即退出）"
dbus-run-session -- bash -c '
  set -e
  UUID=$1
  SHELL_VERSION=$2
  USE_STUB=$3

  gsettings set org.gnome.shell enabled-extensions "[\"$UUID\"]"
  gsettings set org.gnome.shell disable-user-extensions false
  # 避免「欢迎使用」对话框每次都挡在窗口中间。
  dconf write /org/gnome/shell/welcome-dialog-last-shown-version "\"$SHELL_VERSION\""

  if [ "$USE_STUB" = 1 ]; then
      # 直接写 dconf 路径，不需要把扩展 schema 塞进 gsettings 的搜索路径。
      dconf write /org/gnome/shell/extensions/deepseek-balance-indicator/api-key "\"dev-stub-key\""
      dconf write /org/gnome/shell/extensions/deepseek-balance-indicator/poll-interval 30
  fi

  exec gnome-shell --devkit --wayland
' _ "$UUID" "$SHELL_VERSION" "$USE_STUB"
