import AppKit
import ApplicationServices
import os

/// 調べるときは `log stream --predicate 'subsystem == "io.kkweb.ocomenu"'` で見る。クリックの位置や他のアプリのことは残さない
let log = Logger(subsystem: "io.kkweb.ocomenu", category: "app")

// Finder とのやり取り。
//
// 読むのは AX、押すのも AX。選択の一覧だけは AppleScript で Finder に尋ねる。
// 複数選択を AX から組み立てるより確実なため。

/// カーソルの下にあったもの
struct FinderHit {
    /// 右クリックされた項目のパス。項目の上でなければ nil
    var path: String?
    /// その項目が選択済みか
    var selected: Bool
    /// その項目がある窓。デスクトップなら nil
    var window: AXUIElement?
}

@MainActor
enum FinderBridge {
    static let bundleID = "com.apple.finder"

    /// 表示ごとの入れ物の識別子。言語に依らない。サイドバーやツールバーはどれにも当たらない
    private static let contentViews: Set<String> = ["ListView", "IconView", "ColumnView", "GalleryView"]

    static var finder: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// アクセシビリティの許可。無ければ設定を開くよう促す（初回だけ出る）
    @discardableResult
    static func ensureTrusted(prompt: Bool) -> Bool {
        // kAXTrustedCheckOptionPrompt は C から来る var なので Swift 6 では触れない。
        // 中身は固定の文字列で、変わることがない
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    // MARK: - カーソルの下

    /// カーソルの下の要素が Finder のものなら、それを返す
    static func finderElement(at point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(
                AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
            let hit
        else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID else { return nil }
        return hit
    }

    /// カーソルの下の要素から入れ物まで辿って、項目のパスと選択の状態を調べる。
    /// 入れ物に着かなければ（サイドバー、ツールバー、窓の縁など）nil
    static func inspect(_ element: AXUIElement) -> FinderHit? {
        var current: AXUIElement? = element
        var path: String?
        var markedSelected = false
        var container: String?
        var window: AXUIElement?

        for _ in 0..<12 {
            guard let e = current else { break }
            let role = string(e, kAXRoleAttribute)

            if let id = string(e, "AXIdentifier"), contentViews.contains(id) {
                container = id
            } else if role == kAXScrollAreaRole,
                parent(e).flatMap({ string($0, kAXRoleAttribute) })
                    == kAXApplicationRole
            {
                // デスクトップは窓を持たず、アプリの直下にスクロール領域がある
                container = "Desktop"
                break
            }

            if container == nil {
                if path == nil { path = url(e) }
                // リスト表示とカラム表示の行はパスを持たず、行の中の名前の欄が持っている
                if path == nil, role == kAXRowRole { path = urlInside(e) }
                if bool(e, kAXSelectedAttribute) == true { markedSelected = true }
            }
            if role == kAXWindowRole {
                window = e
                break
            }
            current = parent(e)
        }

        guard let container else { return nil }
        guard let path else { return FinderHit(path: nil, selected: false, window: window) }

        // カラム表示では、親の列で強調されているフォルダにも選択の印が付く。
        // Finder の本当の選択は一番右の列にあるので、Finder に尋ねる
        let selected =
            container == "ColumnView"
            ? selection().contains(path)
            : markedSelected
        return FinderHit(path: path, selected: selected, window: window)
    }

    /// その窓が Finder の前面の窓か。デスクトップは Finder が前面なら前面とみなす
    static func isFrontWindow(_ window: AXUIElement?) -> Bool {
        guard let finder, finder.isActive else { return false }
        guard let window else { return true }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        guard let focused = element(app, kAXFocusedWindowAttribute) else { return false }
        return CFEqual(focused, window)
    }

    // MARK: - 選択

    private static let selectionScript: NSAppleScript? = {
        let script = NSAppleScript(
            source: """
                tell application "Finder"
                  set out to ""
                  repeat with i in (get selection)
                    set out to out & POSIX path of (i as alias) & linefeed
                  end repeat
                  return out
                end tell
                """)
        script?.compileAndReturnError(nil)
        return script
    }()

    /// Finder で選ばれている項目のパス。末尾の / は落とす。
    /// 初回は Finder との接続を張るので 100ms ほどかかる。起動時に warmUp で済ませておく
    static func selection() -> [String] {
        var error: NSDictionary?
        guard let result = selectionScript?.executeAndReturnError(&error), error == nil else {
            log.error("selection failed: \(String(describing: error), privacy: .public)")
            return []
        }
        return (result.stringValue ?? "")
            .split(separator: "\n")
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : String($0) }
    }

    /// 初回の問い合わせだけ遅いので、起動時に空打ちしておく。オートメーションの許可もここで求められる
    static func warmUp() {
        _ = selection()
    }

    // MARK: - メニューバー

    /// Finder のメニューバーの項目を押す。押せなければ false
    @discardableResult
    static func press(_ item: BuiltinItem) -> Bool {
        guard let target = menuItem(item, enabledOnly: true) else { return false }
        return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
    }

    /// 今の選択で Finder のメニューバーの項目が使えないもの。自前のメニューからも外す。
    /// ファイルに「新規タブで開く」が出ないのは Finder の右クリックと同じ。
    /// メニューバーに見つからないものは入れない。押して鳴らすほうが、黙って消えるより分かる
    static func unavailableItems() -> Set<BuiltinItem> {
        Set(
            BuiltinItem.allCases.filter { item in
                guard let found = menuItem(item, enabledOnly: false) else { return false }
                // 圧縮のように識別子を2つ持つものは、有効なほうがあれば使える
                return bool(found, kAXEnabledAttribute) != true && menuItem(item, enabledOnly: true) == nil
            })
    }

    /// メニューバーから項目を探す。識別子で探し、無ければ名前で探す
    private static func menuItem(_ item: BuiltinItem, enabledOnly: Bool) -> AXUIElement? {
        guard let finder else { return nil }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        guard let bar = element(app, kAXMenuBarAttribute),
            let menu = children(bar).first(where: { item.menuTitles.contains(string($0, kAXTitleAttribute) ?? "") })
        else { return nil }
        let entries = children(menu)
            .flatMap { string($0, kAXRoleAttribute) == kAXMenuRole ? children($0) : [$0] }
            .filter { !enabledOnly || bool($0, kAXEnabledAttribute) == true }
        return entries.first { string($0, "AXIdentifier").map(item.identifiers.contains) == true }
            ?? MenuMatch.index(of: item.names, in: entries.map { string($0, kAXTitleAttribute) ?? "" })
            .map { entries[$0] }
    }

    /// その窓を前に出し、Finder を前面にする。メニューバーの項目は前面の窓に対して働くため
    static func bringToFront(_ window: AXUIElement?) {
        guard let finder else { return }
        if let window {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        // macOS 14 以降は、自分が持っている前面化の権利を明け渡さないと他のアプリを前に出せない
        NSApp.yieldActivation(to: finder)
        finder.activate()
    }

    // MARK: - AX の小道具

    private static func value(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    private static func string(_ e: AXUIElement, _ name: String) -> String? {
        value(e, name) as? String
    }

    private static func bool(_ e: AXUIElement, _ name: String) -> Bool? {
        value(e, name) as? Bool
    }

    private static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func parent(_ e: AXUIElement) -> AXUIElement? {
        element(e, kAXParentAttribute)
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        (value(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    /// AXURL はファイル参照の形（file:///.file/id=…）で来るので、パスの形に直す
    private static func url(_ e: AXUIElement) -> String? {
        guard let v = value(e, kAXURLAttribute) as? NSURL else { return nil }
        return v.filePathURL?.path
    }

    /// 行の中の欄を2段まで見て、最初に見つかったパス
    private static func urlInside(_ row: AXUIElement) -> String? {
        for cell in children(row) {
            if let path = url(cell) { return path }
            for field in children(cell) {
                if let path = url(field) { return path }
            }
        }
        return nil
    }
}
