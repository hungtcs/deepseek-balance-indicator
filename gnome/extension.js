// 扩展入口：只做接线 —— 读设置、定时请求、把结果交给顶栏指示器。
// 请求细节在 client.js，界面在 indicator.js，设置页在 prefs.js。
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {
    DeepSeekClient,
    DeepSeekError,
    endpointFromEnvironment,
} from './client.js';
import {createIndicator} from './indicator.js';

const MIN_INTERVAL = 5;
const MAX_INTERVAL = 3600;

export default class DeepSeekBalanceExtension extends Extension {
    #settings = null;
    #settingsChangedId = 0;
    #indicator = null;
    #client = null;
    #timerId = 0;
    #cancellable = null;

    #isRefreshing = false;
    #lastBalance = null;
    #lastError = null;
    #lastUpdated = null;

    enable() {
        this.#settings = this.getSettings();
        this.#client = new DeepSeekClient({
            apiKey: this.#apiKey,
            endpoint: endpointFromEnvironment(),
        });

        this.#indicator = createIndicator({
            iconPath: GLib.build_filenamev([this.path, 'icons', 'deepseek-symbolic.svg']),
            version: this.metadata['version-name'] ?? '1.0.0',
            onRefresh: () => this.#refresh(),
            onOpenPreferences: () => this.openPreferences(),
            onOpenUri: uri => this.#openUri(uri),
        });
        Main.panel.addToStatusArea(this.uuid, this.#indicator, 0, 'right');

        this.#settingsChangedId = this.#settings.connect('changed',
            (_settings, key) => this.#onSettingsChanged(key));

        this.#restartTimer();
        this.#render();
        // 启动就请求一次，不用等第一个轮询周期。
        this.#refresh();
    }

    disable() {
        this.#cancelRefresh();
        if (this.#timerId) {
            GLib.source_remove(this.#timerId);
            this.#timerId = 0;
        }
        if (this.#settingsChangedId) {
            this.#settings.disconnect(this.#settingsChangedId);
            this.#settingsChangedId = 0;
        }
        this.#client?.abort();
        this.#indicator?.destroy();

        this.#indicator = null;
        this.#client = null;
        this.#settings = null;
        this.#lastBalance = null;
        this.#lastError = null;
        this.#lastUpdated = null;
    }

    /** 给 tests/shell-smoke.js 读，正式会话里没有调用方。 */
    getDiagnostics() {
        return {
            uuid: this.uuid,
            version: this.metadata['version-name'] ?? '',
            configured: this.#isConfigured,
            refreshing: this.#isRefreshing,
            error: this.#lastError,
            updatedText: this.#lastUpdated?.format('%H:%M:%S') ?? null,
            panel: this.#indicator?.getDiagnostics() ?? null,
        };
    }

    get #apiKey() {
        return (this.#settings?.get_string('api-key') ?? '').trim();
    }

    get #isConfigured() {
        return this.#apiKey.length > 0;
    }

    get #pollInterval() {
        const value = this.#settings?.get_int('poll-interval') ?? 30;
        return Math.min(MAX_INTERVAL, Math.max(MIN_INTERVAL, value));
    }

    #onSettingsChanged(key) {
        if (key === 'poll-interval') {
            this.#restartTimer();
            this.#render();
            return;
        }
        if (key !== 'api-key')
            return;

        this.#client.apiKey = this.#apiKey;
        this.#restartTimer();
        // 换 Key 时旧请求已经没有意义，取消后立刻用新 Key 再请求一次。
        this.#cancelRefresh();
        this.#refresh();
    }

    #restartTimer() {
        if (this.#timerId) {
            GLib.source_remove(this.#timerId);
            this.#timerId = 0;
        }
        this.#timerId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT, this.#pollInterval, () => {
                this.#refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    #cancelRefresh() {
        if (this.#cancellable) {
            this.#cancellable.cancel();
            this.#cancellable = null;
        }
        this.#isRefreshing = false;
    }

    async #refresh() {
        if (!this.#isConfigured) {
            // 没 Key 时不发请求，也不显示错误 —— 只把界面回到「未配置」。
            this.#cancelRefresh();
            this.#lastBalance = null;
            this.#lastError = null;
            this.#lastUpdated = null;
            this.#render();
            return;
        }
        if (this.#isRefreshing)
            return;

        this.#isRefreshing = true;
        this.#render();

        const cancellable = new Gio.Cancellable();
        this.#cancellable = cancellable;
        this.#client.apiKey = this.#apiKey;

        try {
            const response = await this.#client.fetchBalance(cancellable);
            if (this.#cancellable !== cancellable)
                return;

            this.#lastBalance = response.balanceInfos[0] ?? null;
            this.#lastError = this.#lastBalance ? null : '接口未返回余额信息';
            this.#lastUpdated = GLib.DateTime.new_now_local();
        } catch (e) {
            if (this.#cancellable !== cancellable)
                return;
            // 请求失败保留上一次成功的余额，只在菜单里写原因 —— 和 macOS 一致。
            this.#lastError = e instanceof DeepSeekError
                ? e.message
                : `网络错误：${e.message}`;
        } finally {
            if (this.#cancellable === cancellable) {
                this.#cancellable = null;
                this.#isRefreshing = false;
                this.#render();
            }
        }
    }

    #render() {
        this.#indicator?.update({
            configured: this.#isConfigured,
            balance: this.#lastBalance,
            error: this.#lastError,
            refreshing: this.#isRefreshing,
            intervalSeconds: this.#pollInterval,
            updatedText: this.#lastUpdated?.format('%H:%M:%S') ?? null,
        });
    }

    #openUri(uri) {
        try {
            Gio.AppInfo.launch_default_for_uri(uri, null);
        } catch (e) {
            Main.notify('无法打开链接', e.message);
        }
    }
}
