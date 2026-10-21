// 顶栏指示器，对齐 macOS 的 StatusBarController：
// 图标 + 余额，点开是明细、刷新和设置入口。
//
// 用工厂函数而不是 GObject.registerClass：这个控件没有自己的信号和属性，
// 闭包里的 state 已经够用，也省得和 GObject 的 _init 签名较劲。
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {formatGranted, formatToppedUp, formatTotal} from './client.js';

const PLATFORM_URL = 'https://platform.deepseek.com';
const API_KEYS_URL = 'https://platform.deepseek.com/api_keys';

/**
 * @param {object} options
 * @param {string} options.iconPath 扩展目录下的鲸鱼 symbolic 图标
 * @param {string} options.version 显示在「关于」里的版本号
 * @param {Function} options.onRefresh 点「立即刷新」
 * @param {Function} options.onOpenPreferences 点「设置」
 * @param {Function} options.onOpenUri 打开外部链接
 * @returns {PanelMenu.Button}
 */
export function createIndicator({
    iconPath,
    version,
    onRefresh,
    onOpenPreferences,
    onOpenUri,
}) {
    const button = new PanelMenu.Button(0.0, 'DeepSeek 余额指示器');

    let state = {
        configured: false,
        balance: null,
        error: null,
        refreshing: false,
        intervalSeconds: 30,
        updatedText: null,
    };

    const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
    const icon = new St.Icon({
        gicon: Gio.icon_new_for_string(iconPath),
        style_class: 'system-status-icon',
    });
    const label = new St.Label({
        text: '',
        y_align: Clutter.ActorAlign.CENTER,
        style_class: 'deepseek-balance-label',
    });
    box.add_child(icon);
    box.add_child(label);
    button.add_child(box);

    const configureItem = new PopupMenu.PopupImageMenuItem(
        '点击配置 API Key…', 'preferences-system-symbolic');
    configureItem.connect('activate', () => onOpenPreferences?.());

    const balanceItem = new PopupMenu.PopupMenuItem('', {reactive: false});
    const detailItem = new PopupMenu.PopupMenuItem('', {reactive: false});
    const statusItem = new PopupMenu.PopupMenuItem('', {reactive: false});
    const separatorAfterStatus = new PopupMenu.PopupSeparatorMenuItem();

    const refreshItem = new PopupMenu.PopupImageMenuItem('立即刷新', 'view-refresh-symbolic');
    refreshItem.connect('activate', () => onRefresh?.());
    const separatorAfterRefresh = new PopupMenu.PopupSeparatorMenuItem();

    const settingsItem = new PopupMenu.PopupImageMenuItem('设置…', 'preferences-system-symbolic');
    settingsItem.connect('activate', () => onOpenPreferences?.());

    const aboutItem = new PopupMenu.PopupSubMenuMenuItem('关于', true);
    aboutItem.menu.addMenuItem(new PopupMenu.PopupMenuItem(
        `DeepSeek 余额指示器 ${version}`, {reactive: false}));
    const platformItem = new PopupMenu.PopupImageMenuItem(
        '打开 DeepSeek 开放平台', 'web-browser-symbolic');
    platformItem.connect('activate', () => onOpenUri?.(PLATFORM_URL));
    aboutItem.menu.addMenuItem(platformItem);
    const keysItem = new PopupMenu.PopupImageMenuItem(
        '管理 API Key', 'dialog-password-symbolic');
    keysItem.connect('activate', () => onOpenUri?.(API_KEYS_URL));
    aboutItem.menu.addMenuItem(keysItem);

    // 顺序对齐 macOS 菜单：未配置时只有「配置」一项，配置后展开明细。
    const entries = [
        {kind: 'item', item: configureItem},
        {kind: 'item', item: balanceItem},
        {kind: 'item', item: detailItem},
        {kind: 'item', item: statusItem},
        {kind: 'separator', item: separatorAfterStatus},
        {kind: 'item', item: refreshItem},
        {kind: 'separator', item: separatorAfterRefresh},
        {kind: 'item', item: settingsItem},
        {kind: 'submenu', item: aboutItem},
    ];
    for (const {item} of entries)
        button.menu.addMenuItem(item);

    const render = () => {
        const {configured} = state;

        // 未配置时只留鲸鱼图标：没有数字可显示，占位符反而像出了错。
        label.visible = configured;
        if (configured) {
            if (state.balance)
                label.text = formatTotal(state.balance);
            else
                label.text = state.error ? '--' : '…';
        } else {
            label.text = '';
        }

        configureItem.visible = !configured;
        balanceItem.visible = configured;
        detailItem.visible = configured;
        statusItem.visible = configured;
        separatorAfterStatus.visible = configured;
        refreshItem.visible = configured;
        separatorAfterRefresh.visible = configured;

        // 未配置时没有可刷新的东西，其余状态也都没有意义。
        if (!configured)
            return;

        if (state.balance) {
            const total = GLib.markup_escape_text(formatTotal(state.balance), -1);
            balanceItem.label.clutter_text.set_markup(`可用余额   <b>${total}</b>`);
            detailItem.label.text =
                `赠送 ${formatGranted(state.balance)}   ·   充值 ${formatToppedUp(state.balance)}`;
        } else {
            // 和上面的 <b> 一样走 markup，避免残留粗体属性。
            balanceItem.label.clutter_text.set_markup(
                `可用余额   ${state.refreshing ? '读取中…' : '—'}`);
            detailItem.label.text = '尚未获取到余额';
        }

        if (state.error) {
            statusItem.label.text = `⚠︎ ${state.error}`;
            statusItem.label.add_style_class_name('deepseek-menu-error');
        } else {
            statusItem.label.remove_style_class_name('deepseek-menu-error');
            const interval = intervalText(state.intervalSeconds);
            statusItem.label.text = state.updatedText
                ? `每 ${interval}刷新一次，更新于 ${state.updatedText}`
                : `每 ${interval}刷新一次`;
        }

        refreshItem.label.text = state.refreshing ? '刷新中…' : '立即刷新';
        refreshItem.setSensitive(!state.refreshing);
    };

    button.update = next => {
        state = {...state, ...next};
        render();
    };

    /** 给 --automation-script 的验收测试读，避免测试去戳私有成员。 */
    button.getDiagnostics = () => ({
        configured: state.configured,
        label: label.text,
        labelVisible: label.visible,
        balance: state.balance,
        error: state.error,
        refreshing: state.refreshing,
        intervalSeconds: state.intervalSeconds,
        updatedText: state.updatedText,
        menu: entries.map(({kind, item}) => ({
            kind,
            label: kind === 'separator' ? '' : item.label?.text ?? '',
            visible: item.visible,
        })),
    });

    render();
    return button;
}

function intervalText(seconds) {
    if (seconds >= 60 && seconds % 60 === 0)
        return `${seconds / 60} 分钟`;
    return `${seconds} 秒`;
}
