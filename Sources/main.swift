import AppKit

// メニューバーの常駐。
//
// 本体は Finder の右クリックの横取りで、メニューバーには有効・無効の切り替えと設定の入口だけを置く。

@main
enum Ocomenu {
    static func main() {
        // 画面を出さずに計算だけ確かめる口。直したあとはこれを通す
        if CommandLine.arguments.contains("--selftest") {
            exit(MainActor.assumeIsolated { SelfTest.run() })
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Dock とアプリ切替に出さず、メニューバーだけに常駐する
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var settingsWindow = SettingsWindowController()
    /// 画面を作り直すかの判断に使う。文字列は組み立て時に焼き込まれるため
    private var builtLanguage = Language.resolved
    /// アクセシビリティの許可を待つ間の見直し
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image()
        statusItem.menu = menu
        menu.delegate = self
        buildMenu()

        Interceptor.shared.onMenuRequest = { location, window in
            ContextMenu.shared.show(at: location, window: window)
        }
        startWhenTrusted()

        NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            // queue: .main を指定しているので主で呼ばれる。飛ばずに入る
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.builtLanguage != Language.resolved {
                    self.builtLanguage = Language.resolved
                    let wasVisible = self.settingsWindow.window?.isVisible ?? false
                    self.settingsWindow.close()
                    self.settingsWindow = SettingsWindowController()
                    if wasVisible { self.settingsWindow.show() }
                }
                self.buildMenu()
            }
        }

        // 更新の確認は起動時に1回だけ。見つかったときだけ画面が出る
        Updater.shared.checkQuietly()

        // メニューを押さずに設定画面を出すための入口。見た目を確かめるときに使う
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    /// 許可があればすぐ張る。無ければ一度だけ求め、許可されるまで2秒ごとに見直す
    private func startWhenTrusted() {
        if FinderBridge.ensureTrusted(prompt: true), Interceptor.shared.start() {
            FinderBridge.warmUp()
            return
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            // Timer は主の実行ループから呼ぶ。飛ばずに入る
            MainActor.assumeIsolated {
                guard FinderBridge.ensureTrusted(prompt: false), Interceptor.shared.start() else { return }
                self?.trustTimer?.invalidate()
                self?.trustTimer = nil
                FinderBridge.warmUp()
                self?.buildMenu()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    // MARK: - メニュー

    private func buildMenu() {
        menu.removeAllItems()

        if !Interceptor.shared.isRunning {
            let warning = NSMenuItem(
                title: L.needsAccessibility, action: #selector(openAccessibilitySettings), keyEquivalent: "")
            warning.target = self
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let enabled = NSMenuItem(title: L.enabled, action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = Settings.isEnabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: L.settings, action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 切っている間は絵を薄くして、効いていないことが見て分かるようにする
        statusItem.button?.appearsDisabled = !Settings.isEnabled
        statusItem.isVisible = Settings.showsMenuBarIcon
    }

    /// もう一度開かれたら設定画面を出す。アイコンを隠しているときや、ノッチの裏に隠れて見えないときの入口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    @objc private func toggleEnabled() {
        Settings.isEnabled.toggle()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
