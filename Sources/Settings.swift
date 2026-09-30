import Foundation
import ServiceManagement

// 設定の保存と読み出し。
//
// 数が少ないので UserDefaults に直接置く。メニューの並びは JSON にして1つのキーに入れる。
// ログイン時の起動だけは OS 側が持つ状態なので、こちらでは持たず ServiceManagement に問い合わせる。

enum Settings {
    private static let languageKey = "language"
    private static let layoutKey = "menuLayout"
    private static let enabledKey = "enabled"

    // MARK: - 言語

    /// 既定は「システムに従う」。実際にどちらを使うかは Language.resolved が決める
    static var language: Language {
        get {
            UserDefaults.standard.string(forKey: languageKey)
                .flatMap(Language.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: - 有効・無効

    /// 切っている間は横取りせず、Finder の元のメニューが出る
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: - メニューバーのアイコン

    private static let showsIconKey = "showsMenuBarIcon"

    /// 隠しても、アプリをもう一度開けば設定画面が出る。メニューバーが埋まっているとノッチの裏に隠れて見えないため
    static var showsMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: showsIconKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: showsIconKey)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: - メニューの並び

    /// 保存が無いか読めなければ既定の並び。読むたびに normalized を通し、後から増えた標準の項目を足す。
    /// 作り直したり足したりしたら、その場で保存する。行の id は作るたびに変わるので、
    /// 保存しないとメニューを出したときと選ばれたときで id が食い違い、選んでも何も起きない
    static var layout: [MenuEntry] {
        get {
            let saved = UserDefaults.standard.data(forKey: layoutKey)
                .flatMap { try? JSONDecoder().decode([MenuEntry].self, from: $0) }
            let result = saved.map(MenuLayout.normalized) ?? MenuLayout.defaults
            if result != saved, let data = try? JSONEncoder().encode(result) {
                UserDefaults.standard.set(data, forKey: layoutKey)
            }
            return result
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: layoutKey)
            }
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    // MARK: - ログイン時の起動

    /// 状態は OS 側が持っているので、こちらでは覚えず毎回問い合わせる
    static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 切り替えに失敗したら理由を返す。成功なら nil
    static func setLaunchesAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("ocomenu.settingsChanged")
}
