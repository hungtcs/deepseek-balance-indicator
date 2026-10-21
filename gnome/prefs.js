// 设置窗口。跑在独立的 GTK 进程里，不在 Shell 进程中 —— 所以这里只能
// import 与 Shell 无关的模块。改动经 GSettings 交给扩展，立即生效。
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';
import {DeepSeekClient, endpointFromEnvironment, formatTotal} from './client.js';

const API_KEYS_URL = 'https://platform.deepseek.com/api_keys';

export default class DeepSeekBalancePreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage({
            title: '通用',
            icon_name: 'preferences-system-symbolic',
        });

        // ---- API Key ----
        const keyGroup = new Adw.PreferencesGroup({
            title: 'API Key',
            description: '只保存在本机的 dconf 数据库里，除了 DeepSeek 接口本身不会发往任何地方。',
        });

        const keyRow = new Adw.EntryRow({title: 'API Key'});
        keyRow.set_text(settings.get_string('api-key'));
        // 默认隐藏明文，点眼睛才显示 —— 设置窗口经常在录屏或共享屏幕时打开。
        keyRow.get_delegate().set_visibility(false);

        const revealButton = new Gtk.Button({
            icon_name: 'view-reveal-symbolic',
            valign: Gtk.Align.CENTER,
            tooltip_text: '显示 / 隐藏',
        });
        revealButton.add_css_class('flat');
        revealButton.connect('clicked', () => {
            const entry = keyRow.get_delegate();
            const visible = !entry.get_visibility();
            entry.set_visibility(visible);
            revealButton.icon_name = visible
                ? 'view-conceal-symbolic'
                : 'view-reveal-symbolic';
        });
        keyRow.add_suffix(revealButton);
        keyGroup.add(keyRow);

        const linkRow = new Adw.ActionRow({
            title: '获取 API Key',
            subtitle: '在 DeepSeek 开放平台创建，形如 sk-…',
        });
        const openButton = new Gtk.Button({
            label: '打开',
            valign: Gtk.Align.CENTER,
        });
        openButton.add_css_class('flat');
        openButton.connect('clicked', () => {
            try {
                Gio.AppInfo.launch_default_for_uri(API_KEYS_URL, null);
            } catch (e) {
                console.warn(`无法打开链接：${e.message}`);
            }
        });
        linkRow.add_suffix(openButton);
        keyGroup.add(linkRow);
        page.add(keyGroup);

        // ---- 轮询 ----
        const refreshGroup = new Adw.PreferencesGroup({
            title: '刷新',
            description: '余额在后台按这个间隔请求；修改后点下面的「测试并保存」生效。',
        });
        const adjustment = new Gtk.Adjustment({
            lower: 5,
            upper: 3600,
            step_increment: 1,
            page_increment: 10,
            value: settings.get_int('poll-interval'),
        });
        const intervalRow = new Adw.SpinRow({
            title: '轮询间隔',
            subtitle: '秒。最短 5 秒，最长 3600 秒。',
            adjustment,
            digits: 0,
        });
        refreshGroup.add(intervalRow);
        page.add(refreshGroup);

        // ---- 测试并保存 ----
        const testGroup = new Adw.PreferencesGroup({title: '验证'});
        const testRow = new Adw.ActionRow({
            title: '连接状态',
            subtitle: '尚未测试',
        });
        const testButton = new Gtk.Button({
            label: '测试并保存',
            valign: Gtk.Align.CENTER,
        });
        testButton.add_css_class('suggested-action');
        testRow.add_suffix(testButton);
        testGroup.add(testRow);
        page.add(testGroup);

        let client = null;
        let closed = false;
        testButton.connect('clicked', async () => {
            const apiKey = keyRow.get_text().trim();
            const interval = Math.round(intervalRow.get_value());

            // 和 macOS 的「测试并保存」一致：先保存两项设置，再用刚填的 Key
            // 请求一次。保存后扩展会自己重开轮询，不依赖这次测试的结果。
            settings.set_string('api-key', apiKey);
            settings.set_int('poll-interval', interval);

            if (!apiKey) {
                setResult(testRow, '未填写 API Key', 'error');
                return;
            }

            client?.abort();
            client = new DeepSeekClient({
                apiKey,
                endpoint: endpointFromEnvironment(),
            });

            testButton.set_sensitive(false);
            setResult(testRow, '正在请求…', null);
            try {
                const response = await client.fetchBalance();
                if (closed)
                    return;
                const balance = response.balanceInfos[0];
                if (balance)
                    setResult(testRow, `✓ 连接成功 · 可用余额 ${formatTotal(balance)}`, 'success');
                else
                    setResult(testRow, '连接成功，但接口未返回余额信息', 'error');
            } catch (e) {
                if (!closed)
                    setResult(testRow, `✗ ${e.message}`, 'error');
            } finally {
                if (!closed)
                    testButton.set_sensitive(true);
            }
        });

        window.connect('close-request', () => {
            // 关窗时取消在途请求；控件马上会被销毁，回调里不能再碰它们。
            closed = true;
            client?.abort();
            return false;
        });

        window.add(page);
        window.set_default_size(640, 520);
    }
}

function setResult(row, text, cssClass) {
    row.set_subtitle(text);
    row.remove_css_class('success');
    row.remove_css_class('error');
    if (cssClass)
        row.add_css_class(cssClass);
}
