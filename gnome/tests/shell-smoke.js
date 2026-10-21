// GNOME Shell 内的冒烟测试，由 gnome-shell-test-tool 加载。
//
//   gnome-shell-test-tool --headless --extension <zip> tests/shell-smoke.js
//
// 测试自己在 Shell 进程里起一个 Soup 桩服务，再通过扩展的 GSettings
// 模拟「填入 Key → 拿到余额 → Key 失效 → 清空 Key」的完整路径。
// 扩展里没有为测试开洞：断言只读 getDiagnostics() 和顶栏实际控件。
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Soup from 'gi://Soup?version=3.0';
import * as Scripting from 'resource:///org/gnome/shell/ui/scripting.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const UUID = 'deepseek-balance-indicator@hungtcs.dev';
const PORT = Number(GLib.getenv('DEEPSEEK_TEST_PORT') ?? '18765');

export const METRICS = {};

let server;

function respond(message, status, body) {
    message.set_status(status, status === 200 ? 'OK' : 'Error');
    message.set_response('application/json', Soup.MemoryUse.COPY,
        new TextEncoder().encode(JSON.stringify(body)));
}

export function init() {
    server = new Soup.Server();
    server.add_handler('/user/balance', (_server, message) => {
        if (message.get_request_headers().get_one('Authorization') === 'Bearer good-key') {
            respond(message, 200, {
                is_available: true,
                balance_infos: [{
                    currency: 'CNY',
                    total_balance: '110.00',
                    granted_balance: '10.00',
                    topped_up_balance: '100.00',
                }],
            });
        } else {
            respond(message, 401, {error: {message: 'Authentication Fails'}});
        }
    });
    server.listen_local(PORT, Soup.ServerListenOptions.IPV4_ONLY);
    console.log(`[deepseek-test] 桩服务已监听 127.0.0.1:${PORT}`);
}

function check(condition, message) {
    if (!condition)
        throw new Error(message);
    console.log(`[deepseek-test] ok - ${message}`);
}

async function waitFor(predicate, description, timeoutMs = 8000) {
    const deadline = GLib.get_monotonic_time() + timeoutMs * 1000;
    while (GLib.get_monotonic_time() < deadline) {
        if (predicate())
            return;
        await Scripting.sleep(100);
    }
    throw new Error(`等待超时：${description}`);
}

function visibleLabels(diagnostics) {
    return diagnostics.panel.menu
        .filter(entry => entry.visible && entry.kind !== 'separator')
        .map(entry => entry.label);
}

function someVisible(diagnostics, text) {
    return visibleLabels(diagnostics).some(label => label.includes(text));
}

/**
 * 真正打开一次设置窗口。prefs.js 加载失败时 ExtensionPrefsDialog 会把标题
 * 改成「Extension Error」并显示错误页，所以标题等于扩展名就说明 UI 建出来了。
 *
 * 设置窗口是 D-Bus 激活的独立 GTK 进程。run-shell-test.sh 把临时
 * WAYLAND_DISPLAY / XDG_* 放在 dbus-run-session 之外，那个进程才会看到
 * 无头测试桌面，而不是当前真实会话。
 */
async function checkPreferences() {
    const before = new Set(global.display.list_all_windows().map(window => window.get_id()));
    const proc = Gio.Subprocess.new(
        ['gnome-extensions', 'prefs', UUID],
        Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);

    try {
        const deadline = GLib.get_monotonic_time() + 20000 * 1000;
        while (GLib.get_monotonic_time() < deadline) {
            const windows = global.display.list_all_windows()
                .filter(window => !before.has(window.get_id()));

            const settingsWindow = windows.find(
                window => window.get_title() === 'DeepSeek 余额指示器');
            if (settingsWindow) {
                check(true, '设置窗口加载出 UI');
                settingsWindow.delete(global.get_current_time());
                await Scripting.sleep(300);
                return;
            }

            const errorWindow = windows.find(
                window => /error|错误/i.test(window.get_title() ?? ''));
            if (errorWindow)
                throw new Error(`设置窗口加载失败：${errorWindow.get_title()}`);

            await Scripting.sleep(100);
        }
        throw new Error('设置窗口在 20 秒内没有出现');
    } finally {
        if (!proc.get_if_exited())
            proc.force_exit();
    }
}

export async function run() {
    const endpoint = GLib.getenv('DEEPSEEK_BALANCE_ENDPOINT');
    check(Boolean(endpoint), '测试端点由 DEEPSEEK_BALANCE_ENDPOINT 指定');
    check(endpoint.includes(`:${PORT}/`), '测试端点指向桩服务端口');

    const extension = Extension.lookupByUUID(UUID);
    check(Boolean(extension), '扩展已加载');

    // ---- 未配置 ----
    let diagnostics = extension.getDiagnostics();
    check(Boolean(diagnostics.panel), '顶栏指示器已创建');
    check(diagnostics.configured === false, '初始状态未配置');
    check(diagnostics.panel.labelVisible === false, '未配置时顶栏不显示金额');
    check(diagnostics.panel.label === '', '未配置时金额文本为空');
    check(someVisible(diagnostics, '点击配置 API Key'), '菜单显示配置入口');
    check(!someVisible(diagnostics, '可用余额'), '未配置时菜单不显示余额块');

    // ---- 填入有效 Key ----
    const settings = extension.getSettings();
    settings.set_string('api-key', 'good-key');
    await waitFor(() => extension.getDiagnostics().panel?.label === '¥110.00',
        '顶栏显示余额');

    diagnostics = extension.getDiagnostics();
    check(diagnostics.configured === true, '配置状态已切换');
    check(diagnostics.panel.labelVisible === true, '顶栏金额可见');
    check(diagnostics.error === null, '没有错误');
    check(someVisible(diagnostics, '可用余额'), '菜单显示可用余额');
    check(visibleLabels(diagnostics).some(label => label.includes('¥110.00')),
        '菜单金额为 ¥110.00');
    check(someVisible(diagnostics, '赠送 ¥10.00'), '菜单显示赠送明细');
    check(someVisible(diagnostics, '充值 ¥100.00'), '菜单显示充值明细');
    check(someVisible(diagnostics, '每 30 秒刷新一次'), '菜单显示默认轮询间隔');
    check(someVisible(diagnostics, '更新于'), '菜单显示更新时间');
    check(someVisible(diagnostics, '立即刷新'), '菜单显示刷新入口');
    check(!someVisible(diagnostics, '点击配置 API Key'), '已配置后隐藏配置入口');

    // ---- 修改轮询间隔 ----
    settings.set_int('poll-interval', 5);
    await waitFor(() => someVisible(extension.getDiagnostics(), '每 5 秒刷新一次'),
        '菜单跟随轮询间隔设置');

    // ---- Key 失效：保留上次余额，错误写进菜单 ----
    settings.set_string('api-key', 'bad-key');
    await waitFor(() => extension.getDiagnostics().error?.includes('401'),
        '401 错误写进菜单');

    diagnostics = extension.getDiagnostics();
    check(diagnostics.panel.label === '¥110.00', '请求失败时保留上次余额');
    check(someVisible(diagnostics, '401'), '菜单显示 401 错误');

    // ---- 清空 Key：回到未配置，错误一并清掉 ----
    settings.set_string('api-key', '');
    await waitFor(() => extension.getDiagnostics().panel?.labelVisible === false,
        '清空 Key 后隐藏金额');

    diagnostics = extension.getDiagnostics();
    check(diagnostics.configured === false, '清空后配置状态为未配置');
    check(diagnostics.error === null, '清空后不再显示旧错误');
    check(someVisible(diagnostics, '点击配置 API Key'), '清空后恢复配置入口');

    // ---- 设置窗口能加载 ----
    await checkPreferences();

    console.log('[deepseek-test] PASS all checks');
}

export function finish() {
    console.log('[deepseek-test] finish');
}
