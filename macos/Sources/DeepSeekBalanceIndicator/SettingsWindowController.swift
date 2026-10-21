import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private static var current: SettingsWindowController?

    static func show() {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            let controller = SettingsWindowController()
            current = controller
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let hosting = NSHostingController(rootView: SettingsView(store: .shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    @State private var apiKey: String
    @State private var interval: Double
    @State private var revealKey = false
    @State private var message = "填入 API Key 后点「测试并保存」，会先保存再验证一次连接。"
    @State private var messageColor: Color = .secondary
    @State private var isBusy = false

    init(store: SettingsStore) {
        self.store = store
        _apiKey = State(initialValue: store.apiKey)
        _interval = State(initialValue: store.pollInterval)
    }

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("API Key") {
                HStack(spacing: 8) {
                    keyField
                    Button(isBusy ? "测试中…" : "测试并保存") { testAndSave() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBusy || trimmedKey.isEmpty)
                }
                HStack(spacing: 4) {
                    Text("在 DeepSeek 开放平台创建：")
                    Link("platform.deepseek.com/api_keys", destination: AppInfo.apiKeysURL)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            section("轮询间隔") {
                HStack(spacing: 8) {
                    TextField("", value: $interval, format: .number.precision(.fractionLength(0)))
                        .frame(width: 72)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $interval, in: SettingsStore.minPollInterval...SettingsStore.maxPollInterval, step: 5)
                        .labelsHidden()
                    Text("秒")
                    Spacer()
                    Text("默认 30 秒，最小 \(Int(SettingsStore.minPollInterval)) 秒")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Label(message, systemImage: icon(for: messageColor))
                .font(.callout)
                .foregroundStyle(messageColor)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
        }
        .padding(20)
        .frame(width: 520)
    }

    /// Secure/plain field with the reveal toggle tucked inside the box.
    private var keyField: some View {
        ZStack(alignment: .trailing) {
            Group {
                if revealKey {
                    TextField("sk-…", text: $apiKey)
                } else {
                    SecureField("sk-…", text: $apiKey)
                }
            }
            .textFieldStyle(.roundedBorder)

            Button {
                revealKey.toggle()
            } label: {
                Image(systemName: revealKey ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 7)
            .help(revealKey ? "隐藏 API Key" : "显示 API Key")
        }
    }

    private func icon(for color: Color) -> String {
        switch color {
        case .red: return "exclamationmark.triangle.fill"
        case .green: return "checkmark.circle.fill"
        default: return "info.circle"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Saves first, then verifies the saved key against the API.
    private func testAndSave() {
        store.save(apiKey: apiKey, pollInterval: interval)
        apiKey = store.apiKey
        interval = store.pollInterval

        isBusy = true
        message = "已保存，正在测试连接…"
        messageColor = .secondary

        let key = trimmedKey
        Task { @MainActor in
            do {
                let response = try await DeepSeekClient(apiKey: key).fetchBalance()
                if let info = response.balanceInfos.first {
                    message = "已保存。连接成功，可用余额 \(info.displayTotal)（赠送 \(info.displayGranted) · 充值 \(info.displayToppedUp)）"
                } else {
                    message = "已保存。连接成功，但接口未返回余额信息。"
                }
                messageColor = .green
            } catch {
                message = "已保存，但测试失败：" + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                messageColor = .red
            }
            isBusy = false
        }
    }
}
