// client.js 的单元测试：起一个本地 Soup 桩服务，真实走一遍 HTTP。
//
// 运行：gjs -m tests/client.test.js
import GLib from 'gi://GLib';
import Soup from 'gi://Soup?version=3.0';
import * as System from 'system';
import {
    DeepSeekClient,
    DeepSeekError,
    formatGranted,
    formatToppedUp,
    formatTotal,
    parseBalanceResponse,
} from '../client.js';

const GOOD_BODY = {
    is_available: true,
    balance_infos: [{
        currency: 'CNY',
        total_balance: '110.00',
        granted_balance: '10.00',
        topped_up_balance: '100.00',
    }],
};

let server;
let endpoint;
let requestCount = 0;

function reason(status) {
    switch (status) {
    case 200: return 'OK';
    case 401: return 'Unauthorized';
    case 500: return 'Internal Server Error';
    case 503: return 'Service Unavailable';
    default: return '';
    }
}

function respond(message, status, body) {
    message.set_status(status, reason(status));
    const text = typeof body === 'string' ? body : JSON.stringify(body);
    message.set_response('application/json', Soup.MemoryUse.COPY,
        new TextEncoder().encode(text));
}

function startServer() {
    server = new Soup.Server();
    server.add_handler('/user/balance', (_server, message) => {
        requestCount++;
        switch (message.get_request_headers().get_one('Authorization')) {
        case 'Bearer good-key':
            respond(message, 200, GOOD_BODY);
            break;
        case 'Bearer empty-key':
            respond(message, 200, {is_available: true, balance_infos: []});
            break;
        case 'Bearer bad-json':
            respond(message, 200, 'not json');
            break;
        case 'Bearer malformed':
            respond(message, 200, {is_available: true, balance_infos: 'nope'});
            break;
        case 'Bearer server-error':
            respond(message, 500, {error: {message: 'boom'}});
            break;
        case 'Bearer plain-error':
            respond(message, 503, 'down');
            break;
        default:
            respond(message, 401, {error: {message: 'Authentication Fails'}});
            break;
        }
    });
    server.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
    endpoint = `${server.get_uris()[0].to_string().replace(/\/$/, '')}/user/balance`;
}

let passed = 0;
let failed = 0;

async function test(name, fn) {
    try {
        await fn();
        passed++;
        print(`ok ${passed + failed} - ${name}`);
    } catch (e) {
        failed++;
        print(`not ok ${passed + failed} - ${name}\n  ${e.message}`);
    }
}

function assert(condition, message) {
    if (!condition)
        throw new Error(message);
}

function assertEqual(actual, expected, message) {
    if (actual !== expected)
        throw new Error(`${message}：期望 ${JSON.stringify(expected)}，实际 ${JSON.stringify(actual)}`);
}

async function expectError(promise, code, message) {
    try {
        await promise;
    } catch (e) {
        assert(e instanceof DeepSeekError, `${message}：应抛出 DeepSeekError，实际是 ${e}`);
        assertEqual(e.code, code, `${message} 的错误码`);
        return e;
    }
    throw new Error(`${message}：应抛错但没有`);
}

startServer();

await test('成功请求解析出余额与明细', async () => {
    const client = new DeepSeekClient({apiKey: 'good-key', endpoint});
    const response = await client.fetchBalance();
    assertEqual(response.isAvailable, true, 'is_available');
    assertEqual(response.balanceInfos.length, 1, '余额条数');
    const balance = response.balanceInfos[0];
    assertEqual(formatTotal(balance), '¥110.00', '总额');
    assertEqual(formatGranted(balance), '¥10.00', '赠送');
    assertEqual(formatToppedUp(balance), '¥100.00', '充值');
});

await test('API Key 前后空白会被去掉', async () => {
    const client = new DeepSeekClient({apiKey: '  good-key\n', endpoint});
    const response = await client.fetchBalance();
    assertEqual(response.balanceInfos.length, 1, '余额条数');
});

await test('空 Key 直接报错且不发请求', async () => {
    const before = requestCount;
    await expectError(
        new DeepSeekClient({apiKey: '   ', endpoint}).fetchBalance(),
        'missing-key', '空 Key');
    assertEqual(requestCount, before, '请求次数不应变化');
});

await test('401 映射成 unauthorized', async () => {
    await expectError(
        new DeepSeekClient({apiKey: 'wrong-key', endpoint}).fetchBalance(),
        'unauthorized', '401');
});

await test('连接失败映射成 network 错误', async () => {
    // 起一个服务拿到空闲端口，再立刻关掉 —— 比硬编码端口可靠。
    const dead = new Soup.Server();
    dead.listen_local(0, Soup.ServerListenOptions.IPV4_ONLY);
    const uri = dead.get_uris()[0].to_string().replace(/\/$/, '');
    dead.disconnect();

    const error = await expectError(
        new DeepSeekClient({apiKey: 'x', endpoint: `${uri}/user/balance`}).fetchBalance(),
        'network', '连接失败');
    assert(error.message.includes('网络错误'), '信息里应有网络错误');
});

await test('HTTP 错误带上服务端 message', async () => {
    const error = await expectError(
        new DeepSeekClient({apiKey: 'server-error', endpoint}).fetchBalance(),
        'http', '500');
    assert(error.message.includes('500'), '信息里应有状态码');
    assert(error.message.includes('boom'), '信息里应有服务端说明');
});

await test('错误响应不是 JSON 时仍能给出状态码', async () => {
    const error = await expectError(
        new DeepSeekClient({apiKey: 'plain-error', endpoint}).fetchBalance(),
        'http', '503');
    assert(error.message.includes('503'), '信息里应有状态码');
});

await test('成功响应不是 JSON 时报 decoding', async () => {
    await expectError(
        new DeepSeekClient({apiKey: 'bad-json', endpoint}).fetchBalance(),
        'decoding', '非 JSON');
});

await test('响应结构不对时报 decoding', async () => {
    await expectError(
        new DeepSeekClient({apiKey: 'malformed', endpoint}).fetchBalance(),
        'decoding', '结构错误');
});

await test('空 balance_infos 原样返回，由调用方决定提示', async () => {
    const response = await new DeepSeekClient({
        apiKey: 'empty-key', endpoint,
    }).fetchBalance();
    assertEqual(response.balanceInfos.length, 0, '余额条数');
});

await test('未知币种退回「金额 + 币种」写法', async () => {
    const response = parseBalanceResponse({
        is_available: true,
        balance_infos: [{
            currency: 'EUR',
            total_balance: '12.34',
            granted_balance: '1.00',
            topped_up_balance: '11.34',
        }],
    });
    assertEqual(formatTotal(response.balanceInfos[0]), '12.34 EUR', '总额');
});

await test('USD 使用 $ 符号', async () => {
    const response = parseBalanceResponse({
        is_available: true,
        balance_infos: [{
            currency: 'USD',
            total_balance: '5.00',
            granted_balance: '0.00',
            topped_up_balance: '5.00',
        }],
    });
    assertEqual(formatTotal(response.balanceInfos[0]), '$5.00', '总额');
});

print(`\n${passed} passed, ${failed} failed`);
System.exit(failed ? 1 : 0);
