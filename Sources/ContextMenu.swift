import AppKit

// 自前の右クリックメニュー。
//
// 並びは Settings.layout から毎回組む。標準の項目は Finder のメニューバーを押して動かし、
// 自分で足した項目は Actions が動かす。

@MainActor
final class ContextMenu: NSObject {
    static let shared = ContextMenu()

    /// メニューを出した窓。項目が選ばれたら、この窓を前に出してから押す
    private var window: AXUIElement?
    /// 開いているメニュー。外をクリックされたら閉じる
    private var openMenu: NSMenu?
    /// 開いている間に項目が選ばれたか
    private var chose = false

    /// 開いているメニューを閉じる。Ocomenu は前面のアプリではないので、
    /// 外をクリックされてもメニューは自分では閉じない
    func close() {
        openMenu?.cancelTracking()
    }

    /// 画面の左上を原点とする位置（CGEvent の座標）に出す
    func show(at location: CGPoint, window: AXUIElement?) {
        self.window = window
        let menu = NSMenu()
        menu.autoenablesItems = false
        let unavailable = FinderBridge.unavailableItems()
        let entries = Settings.layout.map { entry in
            guard case .builtin(let item) = entry.content, unavailable.contains(item) else { return entry }
            var hidden = entry
            hidden.hidden = true
            return hidden
        }
        for entry in MenuLayout.visible(entries) {
            switch entry.content {
            case .separator:
                menu.addItem(.separator())
            case .builtin(let item):
                menu.addItem(makeItem(title: item.label, symbol: Self.symbol(item), entry: entry))
            case .custom(let action):
                menu.addItem(makeItem(title: action.title, symbol: Self.symbol(action.kind), entry: entry))
            }
        }
        guard !menu.items.isEmpty else { return }

        popUp(menu, at: location, window: window)
    }

    /// メニューを出す足場。アプリを前面にしないまま、キー入力を受け取れる窓。
    /// 前面でないアプリのメニューはキー入力を受けず、Esc でも閉じない。キーを自分に送り直しても無視され、
    /// 前面化は Finder 上のクリックからでは断られた（2026-09-30 に実測）
    private lazy var anchor: NSPanel = {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }()

    private func popUp(_ menu: NSMenu, at location: CGPoint, window: AXUIElement?) {
        // AppKit の座標は左下が原点。一番目の画面の高さで裏返す
        let height = NSScreen.screens.first?.frame.height ?? 0
        let point = NSPoint(x: location.x, y: height - location.y)
        anchor.setFrameOrigin(point)
        anchor.makeKeyAndOrderFront(nil)
        defer { anchor.orderOut(nil) }
        openMenu = menu
        chose = false
        Interceptor.shared.menuIsOpen = true
        log.info("showing the menu, \(menu.items.count) rows")
        menu.popUp(positioning: nil, at: .zero, in: anchor.contentView)
        log.info("menu closed, chose=\(self.chose)")
        Interceptor.shared.menuIsOpen = false
        openMenu = nil
    }

    private func makeItem(title: String, symbol: String, entry: MenuEntry) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = entry.id
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        chose = true
        guard let id = sender.representedObject as? UUID,
            let entry = Settings.layout.first(where: { $0.id == id })
        else { return }
        switch entry.content {
        case .builtin(let item):
            FinderBridge.bringToFront(window)
            // 前面化が済むのを待ってから押す。済む前だと項目が無効のまま
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if !FinderBridge.press(item) {
                    log.error("could not press \(item.rawValue, privacy: .public)")
                    NSSound.beep()
                }
            }
        case .custom(let action):
            FinderBridge.bringToFront(window)
            let paths = FinderBridge.selection()
            log.info("custom item chosen, \(paths.count) selected")
            Actions.run(action, on: paths)
        case .separator:
            break
        }
    }

    // MARK: - 絵

    /// Finder の右クリックに付いている絵に寄せる
    static func symbol(_ item: BuiltinItem) -> String {
        switch item {
        case .open: return "arrow.up.forward.app"
        case .openInNewTab: return "plus.square.on.square"
        case .moveToTrash: return "trash"
        case .getInfo: return "info.circle"
        case .rename: return "pencil"
        case .compress: return "archivebox"
        case .duplicate: return "doc.on.doc"
        case .makeAlias: return "arrowshape.turn.up.right"
        case .quickLook: return "eye"
        case .copy: return "doc.on.clipboard"
        case .copyPath: return "link"
        case .share: return "square.and.arrow.up"
        }
    }

    static func symbol(_ kind: CustomAction.Kind) -> String {
        switch kind {
        case .script: return "terminal"
        case .openWith: return "app"
        case .copyTo: return "folder.badge.plus"
        case .moveTo: return "folder"
        }
    }
}

/// 枠の無いパネルは既定ではキー入力を受け取る窓になれない
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
