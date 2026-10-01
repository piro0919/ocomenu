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
        let items = menuBarItems()
        guard let index = MenuMatch.find(item, in: items.map(\.entry)), items[index].entry.enabled else { return false }
        return AXUIElementPerformAction(items[index].element, kAXPressAction as CFString) == .success
    }

    /// 今の選択で Finder のメニューバーの項目が使えないもの。自前のメニューからも外す。
    /// ファイルに「新規タブで開く」が出ないのは Finder の右クリックと同じ。
    /// メニューバーに見つからないものは入れない。押して鳴らすほうが、黙って消えるより分かる
    static func unavailableItems() -> Set<BuiltinItem> {
        let entries = menuBarItems().map(\.entry)
        return Set(
            BuiltinItem.allCases.filter { item in
                guard let index = MenuMatch.find(item, in: entries) else { return false }
                return !entries[index].enabled
            })
    }

    /// AX から一度に読む属性。順番は menuBarItems の読み出しと揃える
    private static let menuItemAttributes =
        [
            "AXIdentifier", kAXTitleAttribute, kAXMenuItemCmdCharAttribute, kAXMenuItemCmdGlyphAttribute,
            kAXMenuItemCmdModifiersAttribute, kAXEnabledAttribute,
        ] as CFArray

    /// メニューバーの全部のメニューの項目を、並び順に読む。
    /// 親のメニューは名前で選ばない。「ファイル」「File」は言語で変わり、他の言語の Finder で見つからなくなるため。
    /// 先頭のアップルメニューはシステムのもので Finder の項目は無いので飛ばす
    private static func menuBarItems() -> [(element: AXUIElement, entry: MenuBarEntry)] {
        guard let finder else { return [] }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        return children(bar).dropFirst()
            .flatMap { children($0) }
            .flatMap { string($0, kAXRoleAttribute) == kAXMenuRole ? children($0) : [$0] }
            .map { item in
                // 1項目ずつ6回尋ねると遅いので、まとめて読む。無い属性はエラーの値で返り、下の型変換で落ちる
                var raw: CFArray?
                AXUIElementCopyMultipleAttributeValues(item, menuItemAttributes, [], &raw)
                let values = (raw as? [AnyObject]) ?? []
                func at(_ i: Int) -> AnyObject? { i < values.count ? values[i] : nil }
                let char = at(2) as? String
                let glyph = at(3) as? Int
                return (
                    item,
                    MenuBarEntry(
                        identifier: at(0) as? String,
                        title: (at(1) as? String) ?? "",
                        cmdChar: char?.isEmpty == false ? char : nil,
                        cmdGlyph: glyph == 0 ? nil : glyph,
                        cmdModifiers: (at(4) as? Int) ?? 0,
                        enabled: (at(5) as? Bool) == true
                    )
                )
            }
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
