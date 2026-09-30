import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    private static var current: AboutWindowController?

    static func show() {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            let controller = AboutWindowController()
            current = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "关于"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(AppInfo.name)
                .font(.title2.weight(.semibold))
            Text("版本 \(AppInfo.version)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("个人自用的菜单栏小工具，与 DeepSeek 官方无关。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("DeepSeek 开放平台", destination: AppInfo.platformURL)
                .font(.callout)
            Text("余额数据来自 api.deepseek.com/user/balance，API Key 仅保存在本机，不会发送到其他地方。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 340)
    }
}
