import AppKit
import SwiftUI

// 設定画面。
//
// 並べ替えのある一覧が要るので、ここだけ SwiftUI で組んで窓に載せる。
// 言語を変えると文字列が全部変わるので、そのときは画面ごと作り直す（AppDelegate が行う）。

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = L.settingsTitle
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SettingsView())
        // 窓の大きさは中身に合わせ、変えられないようにする。手本の Finder の画面も同じ。
        // 最初はチェック付きの一覧で組んでいて、一覧の全行の高さまで窓が伸びたので窓の側で決めていた。
        // 一覧をやめたので中身に任せられる。窓の側で決めると、中身の下に空白の帯が残った
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
        self.init(window: window)
    }

    func show() {
        window?.center()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // 前面化は頼むだけで、断られると窓がほかのアプリの後ろに開く（2026-09-30 に踏んだ）。
        // 窓だけは必ず一番手前に出す。押せばそこで前面になる
        window?.orderFrontRegardless()
    }
}

private struct SettingsView: View {
    var body: some View {
        TabView {
            MenuLayoutView()
                .tabItem { Text(L.menuTab) }
            GeneralView()
                .tabItem { Text(L.generalTab) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - メニューの並び

// Finder の「ツールバーをカスタマイズ」を手本にする。左に部品、右に実物そっくりのメニュー。
// 部品をメニューへドラッグすると入り、メニューの行を部品の方へドラッグすると抜ける。

/// ドラッグで運ぶ中身。既にある行か、新しい区切り線
private enum DragToken {
    static func entry(_ id: UUID) -> String { "entry:\(id.uuidString)" }
    static let separator = "separator"

    static func entryID(_ token: String) -> UUID? {
        guard token.hasPrefix("entry:") else { return nil }
        return UUID(uuidString: String(token.dropFirst("entry:".count)))
    }
}

private struct MenuLayoutView: View {
    @State private var entries = Settings.layout
    /// 編集の窓に渡す中身。新しく足すときは id が一覧に無い
    @State private var editing: MenuEntry?
    /// ドラッグ中に、この行の上へ入れようとしている
    @State private var dropBefore: UUID?
    @State private var dropAtEnd = false
    @State private var paletteTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                palette
                preview
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)

            Divider()
            HStack {
                Button(L.resetToDefaults) { entries = MenuLayout.reset(entries) }
                Spacer()
                Button(L.done) { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .onChange(of: entries) { _, new in Settings.layout = new }
        .sheet(item: $editing) { entry in
            CustomActionEditor(entry: entry) { saved in
                if let index = entries.firstIndex(where: { $0.id == saved.id }) {
                    entries[index] = saved
                } else {
                    entries.append(saved)
                }
            }
        }
    }

    // MARK: 部品の一覧

    private var palette: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.paletteHint)
                .font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 16) {
                ForEach(paletteEntries) { entry in
                    tile(for: entry)
                }
                Tile(title: L.separator, symbol: "minus", dimmed: false)
                    .draggable(DragToken.separator)
                Button {
                    editing = MenuEntry(.custom(CustomAction(kind: .script, title: "", value: "")))
                } label: {
                    Tile(title: L.newItem, symbol: "plus", dimmed: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 420, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(paletteTargeted ? Color.accentColor.opacity(0.08) : .clear)
        )
        // メニューの行をここへ落とすと抜ける
        .dropDestination(for: String.self) { tokens, _ in
            for token in tokens { takeOut(token) }
            return true
        } isTargeted: {
            paletteTargeted = $0
        }
    }

    /// 部品の並びは固定する。メニューの並びに合わせて動くと、どこに何があるか分からなくなる。
    /// 標準の項目を決まった順に、そのあと自分で作った項目を作った順に
    private var paletteEntries: [MenuEntry] {
        let builtins = BuiltinItem.allCases.compactMap { item in
            entries.first { $0.content == .builtin(item) }
        }
        let customs = entries.filter {
            if case .custom = $0.content { return true }
            return false
        }
        return builtins + customs
    }

    @ViewBuilder
    private func tile(for entry: MenuEntry) -> some View {
        switch entry.content {
        case .builtin(let item):
            Tile(title: item.label, symbol: ContextMenu.symbol(item), dimmed: !entry.hidden)
                .draggable(DragToken.entry(entry.id))
        case .custom(let action):
            Tile(title: action.title, symbol: ContextMenu.symbol(action.kind), dimmed: !entry.hidden)
                .draggable(DragToken.entry(entry.id))
                .contextMenu {
                    Button(L.edit) { editing = entry }
                    Button(L.remove, role: .destructive) { entries.removeAll { $0.id == entry.id } }
                }
        case .separator:
            EmptyView()
        }
    }

    // MARK: 実物そっくりのメニュー

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.previewTitle)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries.filter { !$0.hidden }) { entry in
                    PreviewRow(entry: entry, insertionAbove: dropBefore == entry.id)
                        .draggable(DragToken.entry(entry.id)) {
                            PreviewRow(entry: entry, insertionAbove: false).frame(width: 220)
                        }
                        .dropDestination(for: String.self) { tokens, _ in
                            for token in tokens { putIn(token, before: entry.id) }
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                dropBefore = entry.id
                            } else if dropBefore == entry.id {
                                dropBefore = nil
                            }
                        }
                }
                // 末尾へ入れるための受け皿。空行に見えないよう低くする
                Rectangle()
                    .fill(.clear)
                    .frame(height: 10)
                    .overlay(alignment: .top) {
                        if dropAtEnd { InsertionLine() }
                    }
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { tokens, _ in
                        for token in tokens { putIn(token, before: nil) }
                        return true
                    } isTargeted: {
                        dropAtEnd = $0
                    }
            }
            .padding(5)
            .frame(width: 240)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        // 左の部品の一覧は、ドロップ先の枠のぶん内側に余白がある。見出しの高さを揃える
        .padding(.top, 12)
    }

    // MARK: 出し入れ

    /// メニューへ入れる。before が nil なら末尾
    private func putIn(_ token: String, before target: UUID?) {
        var moving: MenuEntry
        if token == DragToken.separator {
            moving = MenuEntry(.separator)
        } else if let id = DragToken.entryID(token), let index = entries.firstIndex(where: { $0.id == id }) {
            // 自分の上に落としたときは何もしない
            if id == target { return }
            moving = entries.remove(at: index)
            moving.hidden = false
        } else {
            return
        }
        if let target, let index = entries.firstIndex(where: { $0.id == target }) {
            entries.insert(moving, at: index)
        } else {
            entries.append(moving)
        }
    }

    /// メニューから抜く。区切り線は消し、それ以外は隠して部品の一覧に戻す
    private func takeOut(_ token: String) {
        guard let id = DragToken.entryID(token), let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[index].content == .separator {
            entries.remove(at: index)
        } else {
            entries[index].hidden = true
        }
    }
}

/// 部品の一覧のタイル。Finder のツールバーの部品と同じく、丸い地にアイコン、下に名前
private struct Tile: View {
    let title: String
    let symbol: String
    let dimmed: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 28)
                .background(Capsule().fill(.quaternary))
            Text(title)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 88)
        }
        .opacity(dimmed ? 0.35 : 1)
        .contentShape(Rectangle())
    }
}

/// メニューの1行。右クリックで出るメニューと同じ大きさと並び
private struct PreviewRow: View {
    let entry: MenuEntry
    let insertionAbove: Bool
    @State private var hovering = false

    var body: some View {
        Group {
            switch entry.content {
            case .separator:
                // 線は 1pt しかないので、行の高さ全体を掴めるようにする。線だけだと掴めなかった
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .frame(height: 11)
                    .contentShape(Rectangle())
            case .builtin(let item):
                row(item.label, ContextMenu.symbol(item))
            case .custom(let action):
                row(action.title, ContextMenu.symbol(action.kind))
            }
        }
        .overlay(alignment: .top) {
            if insertionAbove { InsertionLine() }
        }
        .onHover { hovering = $0 }
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(hovering ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hovering ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// ドラッグ中に、どこへ入るかを示す線
private struct InsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 4)
            .offset(y: -1.5)
    }
}

// MARK: - 自分で足す項目

private struct CustomActionEditor: View {
    let entry: MenuEntry
    let onSave: (MenuEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: CustomAction.Kind = .script
    @State private var title = ""
    @State private var value = ""

    init(entry: MenuEntry, onSave: @escaping (MenuEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        if case .custom(let action) = entry.content {
            _kind = State(initialValue: action.kind)
            _title = State(initialValue: action.title)
            _value = State(initialValue: action.value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L.kind, selection: $kind) {
                ForEach(CustomAction.Kind.allCases, id: \.self) { kind in
                    Text(L.kindLabel(kind)).tag(kind)
                }
            }
            .onChange(of: kind) { _, _ in value = "" }

            TextField(L.title, text: $title)

            switch kind {
            case .script:
                Text(L.scriptHint).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $value)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(.separator)
            case .openWith:
                chooser(label: L.application, directories: false)
            case .copyTo, .moveTo:
                chooser(label: L.folder, directories: true)
            }

            HStack {
                Spacer()
                Button(L.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L.save) {
                    var saved = entry
                    saved.content = .custom(CustomAction(kind: kind, title: title, value: value))
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || value.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooser(label: String, directories: Bool) -> some View {
        HStack {
            Text(label)
            Text(value.isEmpty ? "-" : (value as NSString).lastPathComponent)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(L.choose) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = directories
                panel.canChooseFiles = !directories
                panel.allowsMultipleSelection = false
                if !directories {
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowedContentTypes = [.application]
                }
                guard panel.runModal() == .OK, let url = panel.url else { return }
                value = url.path
                // 名前が空なら、選んだものの名前から付ける
                if title.isEmpty {
                    title =
                        directories
                        ? L.kindLabel(kind) + ": " + url.lastPathComponent
                        : url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }
}

// MARK: - 一般

private struct GeneralView: View {
    @State private var launchAtLogin = Settings.launchesAtLogin
    @State private var showsIcon = Settings.showsMenuBarIcon
    @State private var language = Settings.language
    @State private var message: String?

    var body: some View {
        Form {
            Toggle(L.launchAtLogin, isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, new in
                    message = Settings.setLaunchesAtLogin(new).map(L.launchToggleFailed)
                    launchAtLogin = Settings.launchesAtLogin
                }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Toggle(isOn: $showsIcon) {
                Text(L.showMenuBarIcon)
                Text(L.menuBarIconHint)
            }
            .onChange(of: showsIcon) { _, new in Settings.showsMenuBarIcon = new }
            Picker(L.language, selection: $language) {
                ForEach(Language.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .onChange(of: language) { _, new in Settings.language = new }

            Button(L.checkForUpdates) { Updater.shared.checkNow() }

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
            Text("Ocomenu \(version)").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
