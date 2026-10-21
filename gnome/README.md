# DeepSeek 余额指示器 · GNOME Shell 扩展

在 GNOME 顶栏显示 DeepSeek 账户余额。和仓库里的 [macOS 版](../macos/README.md)
互相独立：不共享运行时代码，也不需要同时安装。

## 功能

- 顶栏常驻鲸鱼图标 + 可用余额，默认每 30 秒请求一次
- 点开菜单查看余额、赠送金额、充值金额、更新时间
- 请求失败时顶栏保留上一次成功的余额，菜单里用红色写明原因（401、HTTP 错误、网络错误）
- 未配置 API Key 时只显示鲸鱼图标，菜单里给出配置入口
- 「立即刷新」「设置」「关于」以及 DeepSeek 开放平台链接
- 设置页可填写 API Key、调整轮询间隔（5–3600 秒）、测试并保存

## 系统要求

- GNOME Shell 48 / 49 / 50（在 Fedora 44、GNOME Shell 50.5 上测试）
- 运行时依赖由 GNOME Shell 自带：GJS、libsoup 3、libadwaita
- 构建/安装需要 `gnome-extensions` 和 `zip`
- 集成测试额外需要 `gnome-shell-test-tool`（随 `gnome-shell` 安装）和
  `dbus-run-session`（`dbus-tools`）

## 安装

```bash
cd gnome
make install
```

然后启用：

```bash
gnome-extensions enable deepseek-balance-indicator@hungtcs.dev
```

GNOME 50 的 Wayland 会话对已加载扩展有缓存，**如果顶栏没有立刻出现，
注销并重新登录**，登录后再执行一次上面的 `enable`。第一次登录后可以在
「扩展」应用里确认它处于开启状态。

更新代码后也要重新 `make install`，并注销重登 —— GNOME 50 没有可用的
扩展热重载入口。自动化验证请用下面的测试工具，不必反复登录。

卸载：

```bash
make uninstall
```

## 配置

点顶栏图标 →「设置…」，或运行：

```bash
gnome-extensions prefs deepseek-balance-indicator@hungtcs.dev
```

- **API Key** —— 在 <https://platform.deepseek.com/api_keys> 创建。默认隐藏明文，
  点右侧眼睛切换显示。
- **轮询间隔** —— 默认 30 秒，范围 5–3600 秒。
- **测试并保存** —— 先保存两项设置，再用刚填的 Key 请求一次，把结果显示在
  「连接状态」里。保存后扩展立即按新设置重新轮询。

API Key 保存在本机 dconf：

```bash
dconf read /org/gnome/shell/extensions/deepseek-balance-indicator/api-key
```

它是明文存储的，和 macOS 版使用 `UserDefaults` 的取舍相同；不要把 dconf 数据库
同步到不受信任的地方。

## 测试

### 单元测试（不需要显示器）

```bash
make test
```

起一个本地 Soup 桩服务，真实走 HTTP，覆盖成功、空 Key、401、连接失败、HTTP 5xx、
非 JSON 响应、错误结构、币种格式等 12 个用例。

### 集成测试（无头 GNOME Shell）

```bash
make test-shell
```

用 Fedora 随 `gnome-shell` 安装的 `gnome-shell-test-tool` 启动一个无头的
嵌套 GNOME Shell，把打包后的扩展装进临时 XDG 目录，再运行
`tests/shell-smoke.js`。测试会在 Shell 进程内起桩服务，通过 GSettings 模拟：

1. 未配置时顶栏不显示金额、菜单只有配置入口
2. 填入有效 Key 后顶栏出现 `¥110.00`，菜单显示赠送/充值/更新时间
3. 修改轮询间隔后菜单文字跟着变
4. Key 失效（401）时保留上次余额并在菜单里显示错误
5. 清空 Key 后回到未配置状态，旧错误被清掉
6. 真正打开一次设置窗口，确认 `prefs.js` 加载出 UI 而不是
   「Extension Error」错误页（设置窗口是由 D-Bus 激活的独立 GTK 进程，
   测试环境把它也限制在无头测试桌面上）

整个过程使用独立的 D-Bus 会话、临时 `XDG_RUNTIME_DIR` / `XDG_CONFIG_HOME`
和 keyfile GSettings 后端，不会碰当前登录会话的设置，也不会把测试扩展
装进真实的扩展目录。

## 交互式调试窗口

不想注销重登时，用 `--devkit` 起一个嵌套 Shell，它会以一个小窗口显示在
当前桌面上：

```bash
make dev-session
# 等价于 ./dev-session.sh
```

默认会起一个本地桩服务并把 API Key 预填成 `dev-stub-key`，所以顶栏直接显示
`¥110.00`，菜单明细、立即刷新、设置里的「测试并保存」都可以点。设置窗口也
出现在嵌套 Shell 窗口里，不会跑到真实桌面。

想用真实接口测试：

```bash
USE_STUB=0 ./dev-session.sh
```

然后在顶栏菜单 →「设置…」里填真实 API Key。嵌套会话使用临时
`XDG_CONFIG_HOME` / `XDG_DATA_HOME` 和私有 D-Bus，不会改动你当前登录会话
的扩展与设置；关掉窗口即退出，桩服务一并清理。

修改代码后需要重新运行 `make dev-session`（GNOME 50 没有扩展热重载），
脚本会重新构建 `dist/dev/` 并启动新的嵌套会话。

## 开发

```
gnome/
├── metadata.json          # 扩展元数据（UUID、GNOME 版本、schema 名）
├── extension.js           # 入口：设置、定时器、请求生命周期
├── client.js              # DeepSeek 接口客户端（不依赖 Shell，可单测）
├── indicator.js           # 顶栏按钮与菜单
├── prefs.js               # 设置窗口（Adw）
├── stylesheet.css         # 金额等宽数字、错误颜色
├── icons/
│   └── deepseek-symbolic.svg
├── schemas/               # GSettings schema
├── tests/
│   ├── client.test.js     # gjs 单元测试
│   ├── shell-smoke.js     # gnome-shell-test-tool 自动化脚本
│   └── run-shell-test.sh
└── Makefile
```

常用命令：

| 命令 | 作用 |
| --- | --- |
| `make pack` | 生成 `dist/<uuid>.shell-extension.zip` |
| `make dev-session` | 启动嵌套 GNOME Shell 调试窗口（默认带桩余额） |
| `make dev-bundle` | 只生成 `dist/dev/<uuid>/` 开发目录 |
| `make install` | 打包并安装到 `~/.local/share/gnome-shell/extensions/` |
| `make enable` / `make disable` | 启用 / 禁用 |
| `make prefs` | 打开设置窗口 |
| `make test` | 单元测试 |
| `make test-shell` | 无头 Shell 集成测试 |
| `make check` | 两组测试都跑 |
| `make clean` | 删除 `dist/` |

查看 Shell 日志：

```bash
journalctl --user -f -o cat /usr/bin/gnome-shell | grep -i deepseek
```

### 调试端点

`DEEPSEEK_BALANCE_ENDPOINT` 环境变量可以覆盖请求地址，仅供测试和本地调试：

```bash
DEEPSEEK_BALANCE_ENDPOINT=http://127.0.0.1:8765/user/balance \
  gnome-shell-test-tool --headless --extension dist/*.zip tests/shell-smoke.js
```

正式会话里不会设置这个变量。

### 打包注意

GNOME Shell 50.5 自带的 `gnome-extensions install` 遇到 zip 中的目录条目会报
`Can’t recursively copy directory`。`make pack` 在 `gnome-extensions pack`
之后用 `zip -qd ... '*/'` 删掉目录条目，安装器随后会自行编译
`schemas/gschemas.compiled`。如果上游修复了这个问题，这一步可以去掉。

## 说明

- 余额来自 `GET https://api.deepseek.com/user/balance`，和 macOS 版使用同一个接口。
- 请求带 `Authorization: Bearer <API Key>`，超时 15 秒。
- 失败时保留上一次成功的余额，不把顶栏变成错误状态。
- 鲸鱼图标素材来自 DeepSeek，版权归 DeepSeek 所有；仓库其余代码以根目录
  [MIT License](../LICENSE) 授权。
