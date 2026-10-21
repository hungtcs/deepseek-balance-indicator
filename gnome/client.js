// DeepSeek 余额接口客户端。
//
// 刻意不 import 任何 Shell 模块：设置窗口（独立的 GTK 进程）和单元测试
// 也要用同一份实现。两个进程都不是 Shell，碰 `resource:///org/gnome/shell/...`
// 会直接加载失败。
import GLib from 'gi://GLib';
import Soup from 'gi://Soup?version=3.0';

export const DEFAULT_ENDPOINT = 'https://api.deepseek.com/user/balance';
export const DEFAULT_TIMEOUT = 15;

/** 测试用：把端点指向本地桩服务，正式会话里读不到这个变量。 */
export function endpointFromEnvironment() {
    return GLib.getenv('DEEPSEEK_BALANCE_ENDPOINT') || DEFAULT_ENDPOINT;
}

export class DeepSeekError extends Error {
    constructor(code, message) {
        super(message);
        this.name = 'DeepSeekError';
        this.code = code;
    }
}

export class DeepSeekClient {
    #apiKey;
    #endpoint;
    #session;

    constructor({apiKey = '', endpoint = DEFAULT_ENDPOINT, timeout = DEFAULT_TIMEOUT} = {}) {
        this.#apiKey = apiKey;
        this.#endpoint = endpoint;
        this.#session = new Soup.Session({timeout});
    }

    get apiKey() {
        return this.#apiKey;
    }

    set apiKey(value) {
        this.#apiKey = value;
    }

    get endpoint() {
        return this.#endpoint;
    }

    set endpoint(value) {
        this.#endpoint = value;
    }

    /** 扩展被禁用或窗口关闭时调用，取消所有在途请求。 */
    abort() {
        this.#session.abort();
    }

    async fetchBalance(cancellable = null) {
        const key = this.#apiKey.trim();
        if (!key)
            throw new DeepSeekError('missing-key', '未设置 API Key，请在设置中填写');

        let message;
        try {
            message = Soup.Message.new('GET', this.#endpoint);
        } catch (e) {
            throw new DeepSeekError('network', `无效的接口地址：${e.message}`);
        }
        if (!message)
            throw new DeepSeekError('network', '无效的接口地址');

        message.request_headers.append('Accept', 'application/json');
        message.request_headers.append('Authorization', `Bearer ${key}`);

        let bytes;
        try {
            bytes = await sendAndRead(this.#session, message, cancellable);
        } catch (e) {
            if (cancellable?.is_cancelled())
                throw e;
            throw new DeepSeekError('network', `网络错误：${e.message}`);
        }

        const status = message.get_status();
        const body = new TextDecoder().decode(bytes?.get_data() ?? new Uint8Array());

        if (status === Soup.Status.UNAUTHORIZED)
            throw new DeepSeekError('unauthorized', 'API Key 无效或已过期（401）');

        if (status < 200 || status >= 300) {
            const detail = errorMessage(body);
            throw new DeepSeekError('http',
                `请求失败（HTTP ${status}）${detail ? `：${detail}` : ''}`);
        }

        let json;
        try {
            json = JSON.parse(body);
        } catch {
            throw new DeepSeekError('decoding', '接口返回内容无法解析');
        }

        return parseBalanceResponse(json);
    }
}

function sendAndRead(session, message, cancellable) {
    return new Promise((resolve, reject) => {
        session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, cancellable, (source, result) => {
            try {
                resolve(source.send_and_read_finish(result));
            } catch (e) {
                reject(e);
            }
        });
    });
}

/** `{"error": {"message": "..."}}` 里的错误说明，没有就返回 null。 */
function errorMessage(body) {
    try {
        const message = JSON.parse(body)?.error?.message;
        return typeof message === 'string' ? message : null;
    } catch {
        return null;
    }
}

export function parseBalanceResponse(json) {
    if (!json || typeof json !== 'object' || !Array.isArray(json.balance_infos))
        throw new DeepSeekError('decoding', '接口返回内容无法解析');

    return {
        isAvailable: Boolean(json.is_available),
        balanceInfos: json.balance_infos.map(info => ({
            currency: String(info?.currency ?? ''),
            totalBalance: String(info?.total_balance ?? ''),
            grantedBalance: String(info?.granted_balance ?? ''),
            toppedUpBalance: String(info?.topped_up_balance ?? ''),
        })),
    };
}

export function currencySymbol(currency) {
    switch (String(currency).toUpperCase()) {
    case 'CNY':
        return '¥';
    case 'USD':
        return '$';
    default:
        return '';
    }
}

function display(amount, currency) {
    const symbol = currencySymbol(currency);
    return symbol ? `${symbol}${amount}` : `${amount} ${currency}`.trim();
}

/** `¥110.00`；没有对应符号的币种退回 `110.00 EUR`。 */
export function formatTotal(balance) {
    return display(balance.totalBalance, balance.currency);
}

export function formatGranted(balance) {
    const symbol = currencySymbol(balance.currency);
    return symbol ? `${symbol}${balance.grantedBalance}` : `${balance.grantedBalance} ${balance.currency}`.trim();
}

export function formatToppedUp(balance) {
    const symbol = currencySymbol(balance.currency);
    return symbol ? `${symbol}${balance.toppedUpBalance}` : `${balance.toppedUpBalance} ${balance.currency}`.trim();
}
