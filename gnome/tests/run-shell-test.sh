#!/usr/bin/env bash
# 用 GNOME Shell 自带的测试工具起一个无头 Shell，加载打包后的扩展并跑冒烟测试。
#
# 关键点是 dbus-run-session + 临时 XDG_RUNTIME_DIR：否则测试 Shell 会和
# 当前登录的 Shell 抢同一个 D-Bus 名字（org.gnome.Shell），在真实桌面上
# 直接跑会失败或干扰正在使用的会话。
set -euo pipefail

cd "$(dirname "$0")/.."

UUID=deepseek-balance-indicator@hungtcs.dev
ZIP="dist/$UUID.shell-extension.zip"
PORT="${DEEPSEEK_TEST_PORT:-18765}"

for tool in gnome-shell-test-tool dbus-run-session timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少 $tool（gnome-shell-test-tool 随 gnome-shell 安装）" >&2
        exit 1
    fi
done
if [ ! -f "$ZIP" ]; then
    echo "还没打包：先运行 make pack" >&2
    exit 1
fi

STATE="$(mktemp -d)"
LOG="$STATE/shell.log"
cleanup() {
    # xdg-document-portal 会在 XDG_RUNTIME_DIR 下建 doc/by-app（只读），
    # 清理失败不应把已经通过的测试变成失败。
    chmod -R u+rwX "$STATE" 2>/dev/null || true
    rm -rf "$STATE" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$STATE/runtime" "$STATE/config" "$STATE/data" "$STATE/cache"
chmod 700 "$STATE/runtime"

echo "→ 无头 GNOME Shell，桩服务端口 $PORT"
# 这些变量必须放在 dbus-run-session **外面**：设置窗口由 D-Bus 激活的
# 独立进程打开，它继承的是 dbus-daemon 的环境，而不是 Shell 子进程的环境。
# 放错位置时 prefs 进程会连到当前真实桌面的 Wayland display。
set +e
env \
    XDG_RUNTIME_DIR="$STATE/runtime" \
    XDG_CONFIG_HOME="$STATE/config" \
    XDG_DATA_HOME="$STATE/data" \
    XDG_CACHE_HOME="$STATE/cache" \
    GSETTINGS_BACKEND=keyfile \
    WAYLAND_DISPLAY=gnome-shell-test-display \
    GTK_A11Y=none \
    DEEPSEEK_TEST_PORT="$PORT" \
    DEEPSEEK_BALANCE_ENDPOINT="http://127.0.0.1:$PORT/user/balance" \
    dbus-run-session -- timeout 120 gnome-shell-test-tool --headless \
        --extension "$ZIP" tests/shell-smoke.js > "$LOG" 2>&1
status=$?
set -e

# 完整日志只留在临时目录里；成功时只挑出测试自己的断言行。
grep '\[deepseek-test\]' "$LOG" || true

if ! grep -q '\[deepseek-test\] PASS all checks' "$LOG"; then
    echo "扩展冒烟测试失败（gnome-shell-test-tool 退出码 $status）。完整日志末尾：" >&2
    tail -80 "$LOG" >&2
    exit 1
fi
if [ "$status" -ne 0 ]; then
    echo "扩展冒烟测试通过，但测试 Shell 退出码为 $status" >&2
    exit "$status"
fi

echo "→ 扩展冒烟测试通过"
