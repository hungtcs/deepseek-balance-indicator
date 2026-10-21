import AppKit

@MainActor
final class StatusBarController: NSObject {
    var onOpenSettings: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    /// Set by `--self-test` to point at a stub server instead of api.deepseek.com.
    var endpoint: URL = DeepSeekClient.defaultEndpoint

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let configureItem = NSMenuItem()
    private let balanceItem = NSMenuItem()
    private let detailItem = NSMenuItem()
    private let statusItemInfo = NSMenuItem()
    private let refreshItem = NSMenuItem()
    private let separatorAfterStatus = NSMenuItem.separator()
    private let separatorAfterRefresh = NSMenuItem.separator()

    private var timer: Timer?
    private var isRefreshing = false
    private var lastBalance: BalanceInfo?
    private var lastError: String?
    private var lastUpdated: Date?

    override init() {
        super.init()
        configureButton()
        buildMenu()
        statusItem.menu = menu
        render()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Polling

    func start() {
        restartTimer()
        refresh()
    }

    /// Re-arms the timer using the current interval (called after settings change).
    func restartTimer() {
        timer?.invalidate()
        let interval = SettingsStore.shared.pollInterval
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = min(interval * 0.1, 5)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        refresh()
    }

    var isConfigured: Bool { SettingsStore.shared.hasAPIKey }

    func refresh() {
        guard isConfigured else {
            // Nothing to poll — and no "unavailable" noise — until a key exists.
            isRefreshing = false
            lastBalance = nil
            lastError = nil
            lastUpdated = nil
            render()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        render()

        let key = SettingsStore.shared.apiKey
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await DeepSeekClient(apiKey: key, endpoint: self.endpoint).fetchBalance()
                self.finish(with: .success(response))
            } catch {
                self.finish(with: .failure(error))
            }
        }
    }

    private func finish(with result: Result<BalanceResponse, Error>) {
        isRefreshing = false
        switch result {
        case let .success(response):
            lastBalance = response.balanceInfos.first
            lastError = response.balanceInfos.isEmpty ? "接口未返回余额信息" : nil
            lastUpdated = Date()
        case let .failure(error):
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        render()
    }

    // MARK: - Menu set-up

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.load()
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    private func buildMenu() {
        menu.autoenablesItems = false

        for item in [balanceItem, detailItem, statusItemInfo] {
            item.isEnabled = false
        }
        balanceItem.isEnabled = true // so the title renders at full opacity

        configureItem.title = "点击配置 API Key…"
        configureItem.target = self
        configureItem.action = #selector(settingsClicked)

        refreshItem.title = "立即刷新"
        refreshItem.keyEquivalent = "r"
        refreshItem.target = self
        refreshItem.action = #selector(refreshClicked)

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self

        let aboutItem = NSMenuItem(title: "关于…", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(configureItem)
        menu.addItem(balanceItem)
        menu.addItem(detailItem)
        menu.addItem(statusItemInfo)
        menu.addItem(separatorAfterStatus)
        menu.addItem(refreshItem)
        menu.addItem(separatorAfterRefresh)
        menu.addItem(settingsItem)
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    // MARK: - Rendering

    private func render() {
        renderButton()
        renderMenu()
    }

    private func renderButton() {
        guard let button = statusItem.button else { return }
        guard isConfigured else {
            // Unconfigured: the whale alone, no placeholder amount.
            button.title = ""
            button.toolTip = "\(AppInfo.name)\n尚未配置 API Key，点击菜单进行配置"
            return
        }
        let title: String
        if let balance = lastBalance {
            title = balance.displayTotal
        } else {
            title = lastError == nil ? "…" : "--"
        }
        // A leading space keeps the amount off the whale; when the image is
        // missing the title carries the app identity instead.
        button.title = button.image == nil ? "DS \(title)" : " \(title)"
        button.toolTip = tooltip
    }

    private var tooltip: String {
        var lines = ["\(AppInfo.name)"]
        if let balance = lastBalance {
            lines.append("可用余额 \(balance.displayTotal)")
            lines.append("赠送 \(balance.displayGranted) · 充值 \(balance.displayToppedUp)")
        }
        if let error = lastError { lines.append(error) }
        if let lastUpdated { lines.append("更新于 \(Self.timeFormatter.string(from: lastUpdated))") }
        return lines.joined(separator: "\n")
    }

    private func renderMenu() {
        let configured = isConfigured
        configureItem.isHidden = configured
        balanceItem.isHidden = !configured
        detailItem.isHidden = !configured
        statusItemInfo.isHidden = !configured
        refreshItem.isHidden = !configured
        separatorAfterRefresh.isHidden = !configured
        guard configured else { return }

        if let balance = lastBalance {
            balanceItem.attributedTitle = Self.compose([
                ("可用余额   ", .secondaryLabelColor, .systemFont(ofSize: 13)),
                (balance.displayTotal, .labelColor, .monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
            ])
            detailItem.attributedTitle = Self.compose([
                ("赠送 \(balance.displayGranted)", .secondaryLabelColor, .systemFont(ofSize: 11)),
                ("   ·   ", .tertiaryLabelColor, .systemFont(ofSize: 11)),
                ("充值 \(balance.displayToppedUp)", .secondaryLabelColor, .systemFont(ofSize: 11))
            ])
        } else {
            balanceItem.attributedTitle = Self.compose([
                ("可用余额   ", .secondaryLabelColor, .systemFont(ofSize: 13)),
                (isRefreshing ? "读取中…" : "—", .secondaryLabelColor, .monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
            ])
            detailItem.attributedTitle = Self.compose([
                (SettingsStore.shared.hasAPIKey ? "尚未获取到余额" : "尚未配置 API Key", .tertiaryLabelColor, .systemFont(ofSize: 11))
            ])
        }

        if let error = lastError {
            statusItemInfo.attributedTitle = Self.compose([("⚠︎ \(error)", .systemRed, .systemFont(ofSize: 11))])
        } else if let lastUpdated {
            statusItemInfo.attributedTitle = Self.compose([
                ("每 \(Self.intervalText(SettingsStore.shared.pollInterval)) 刷新一次，更新于 \(Self.timeFormatter.string(from: lastUpdated))",
                 .tertiaryLabelColor, .systemFont(ofSize: 11))
            ])
        } else {
            statusItemInfo.attributedTitle = Self.compose([
                ("每 \(Self.intervalText(SettingsStore.shared.pollInterval)) 刷新一次", .tertiaryLabelColor, .systemFont(ofSize: 11))
            ])
        }

        refreshItem.title = isRefreshing ? "刷新中…" : "立即刷新"
        refreshItem.isEnabled = !isRefreshing
    }

    private static func compose(_ parts: [(String, NSColor, NSFont)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (text, color, font) in parts {
            result.append(NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font]))
        }
        return result
    }

    private static func intervalText(_ seconds: Double) -> String {
        seconds >= 60 && seconds.truncatingRemainder(dividingBy: 60) == 0
            ? "\(Int(seconds / 60)) 分钟"
            : "\(Int(seconds)) 秒"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Diagnostics

    /// Exposed for `--self-test` / `--capture` only.
    var statusBarButton: NSStatusBarButton? { statusItem.button }
    var statusMenu: NSMenu { menu }

    /// Snapshot of what the status item and menu currently show, for `--self-test`.
    func diagnosticsDescription() -> String {
        let button = statusItem.button
        var lines: [String] = []
        lines.append("status item     : \(statusItem.isVisible ? "visible" : "hidden")")
        lines.append("button.image    : \(button?.image == nil ? "nil" : "\(MenuBarIcon.pointSize.width)x\(MenuBarIcon.pointSize.height) pt")")
        lines.append("button.title    : \"\(button?.title ?? "")\"")
        lines.append("button.toolTip  : \(button?.toolTip?.replacingOccurrences(of: "\n", with: " | ") ?? "nil")")
        lines.append("configured      : \(isConfigured)")
        lines.append("error           : \(lastError ?? "none")")
        lines.append("menu items:")
        for item in menu.items {
            if item.isSeparatorItem {
                lines.append("  ---\(item.isHidden ? " (hidden)" : "")")
            } else {
                let attributed = item.attributedTitle?.string ?? ""
                let title = attributed.isEmpty ? item.title : attributed
                let state = item.isHidden ? "hidden" : (item.isEnabled ? "on" : "off")
                lines.append("  [\(state)] \(title)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func refreshClicked() { refresh() }
    @objc private func settingsClicked() { onOpenSettings?() }
    @objc private func aboutClicked() { onOpenAbout?() }
    @objc private func quitClicked() { NSApp.terminate(nil) }
}
