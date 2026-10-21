# DeepSeek 余额指示器

在桌面顶栏 / 菜单栏实时显示 DeepSeek 账户余额。同一份界面行为在两个平台上
各有独立实现，互不依赖：

| 平台                | 形态                                   | 目录                        | 文档                              |
| ------------------- | -------------------------------------- | --------------------------- | --------------------------------- |
| macOS               | 菜单栏应用（Swift · AppKit + SwiftUI） | [`macos/`](macos/README.md) | [macOS 版说明](macos/README.md)   |
| Linux · GNOME Shell | 顶栏扩展（GJS · ESM）                  | [`gnome/`](gnome/README.md) | [GNOME 扩展说明](gnome/README.md) |

两者都可以单独构建、安装和卸载，没有共享的运行时代码；共同的只有接口约定：

- 余额来自 `GET https://api.deepseek.com/user/balance`
- 请求带 `Authorization: Bearer <API Key>`，超时 15 秒
- 默认每 30 秒刷新一次
- 请求失败时保留上一次成功的余额，在菜单 / 下拉里写明原因
- API Key 只保存在本机（macOS `UserDefaults`、GNOME dconf），不经过第三方

## 快速开始

macOS：

```bash
cd macos
./scripts/build-app.sh
open build/DeepSeekBalanceIndicator.app
```

Linux（Fedora / GNOME Shell 48+）：

```bash
cd gnome
make install
gnome-extensions enable deepseek-balance-indicator@hungtcs.dev
# 若顶栏没有立刻出现，注销重新登录后再执行一次 enable
```

详细说明、设置项和测试方式见各平台目录下的 README。

## 仓库结构

```
.
├── macos/        # Swift 菜单栏应用
├── gnome/        # GNOME Shell 扩展（独立工程）
├── LICENSE       # MIT
└── README.md
```

## 测试

- macOS：`macos/` 下的 `--self-test` / `--capture`，见 [macOS 版说明](macos/README.md)
- GNOME：`cd gnome && make test`（单元测试）、`make test-shell`
  （`gnome-shell-test-tool` 无头集成测试），见 [GNOME 扩展说明](gnome/README.md)

## 授权

代码以 [MIT License](LICENSE) 授权。DeepSeek 鲸鱼图标素材来自 DeepSeek，
版权归 DeepSeek 所有。
