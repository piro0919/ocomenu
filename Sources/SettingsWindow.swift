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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = L.settingsTitle
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 420)
        window.contentViewController = NSHostingController(rootView: SettingsView())
        self.init(window: window)
    }

    func show() {
        window?.center()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
        .padding(16)
    }
}

// MARK: - メニューの並び

private struct MenuLayoutView: View {
    @State private var entries = Settings.layout
    @State private var selection: UUID?
    /// 編集の窓に渡す中身。新しく足すときは id が一覧に無い
    @State private var editing: MenuEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.menuHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach($entries) { $entry in
                    EntryRow(entry: $entry)
                        .tag(entry.id)
                        .contextMenu {
                            if case .custom = entry.content {
                                Button(L.edit) { editing = entry }
                            }
                            if isRemovable(entry) {
                                Button(L.remove) { remove(entry.id) }
                            }
                        }
                }
                .onMove { from, to in
                    entries.move(fromOffsets: from, toOffset: to)
                }
            }
            .onChange(of: entries) { _, new in Settings.layout = new }

            HStack {
                Button(L.addAction) {
                    editing = MenuEntry(.custom(CustomAction(kind: .script, title: "", value: "")))
                }
                Button(L.addSeparator) {
                    insert(MenuEntry(.separator))
                }
                Spacer()
                Button(L.remove) {
                    if let selection { remove(selection) }
                }
                .disabled(!(selectedEntry.map(isRemovable) ?? false))
                Button(L.resetToDefaults) {
                    entries = MenuLayout.defaults
                }
            }
        }
        .sheet(item: $editing) { entry in
            CustomActionEditor(entry: entry) { saved in
                if let index = entries.firstIndex(where: { $0.id == saved.id }) {
                    entries[index] = saved
                } else {
                    insert(saved)
                }
            }
        }
    }

    private var selectedEntry: MenuEntry? {
        entries.first { $0.id == selection }
    }

    /// 標準の項目は消さずにチェックを外す。消したものを戻す場所が要るため
    private func isRemovable(_ entry: MenuEntry) -> Bool {
        if case .builtin = entry.content { return false }
        return true
    }

    /// 選んでいる行の下に入れる。何も選んでいなければ末尾
    private func insert(_ entry: MenuEntry) {
        if let selection, let index = entries.firstIndex(where: { $0.id == selection }) {
            entries.insert(entry, at: index + 1)
        } else {
            entries.append(entry)
        }
        selection = entry.id
    }

    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id && isRemovable($0) }
    }
}

private struct EntryRow: View {
    @Binding var entry: MenuEntry

    var body: some View {
        switch entry.content {
        case .separator:
            HStack {
                Rectangle().fill(.separator).frame(height: 1)
                Text(L.separator).font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(.separator).frame(height: 1)
            }
            .opacity(entry.hidden ? 0.4 : 1)
        case .builtin(let item):
            row(title: item.label, symbol: ContextMenu.symbol(item))
        case .custom(let action):
            row(title: action.title, symbol: ContextMenu.symbol(action.kind), detail: L.kindLabel(action.kind))
        }
    }

    private func row(title: String, symbol: String, detail: String? = nil) -> some View {
        Toggle(isOn: Binding(get: { !entry.hidden }, set: { entry.hidden = !$0 })) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
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
