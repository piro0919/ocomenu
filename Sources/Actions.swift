import AppKit

// 自分で足した項目の実行。
//
// どれも選ばれた項目のパスの一覧を受け取る。失敗したら画面で知らせる。黙って何も起きないのが一番困るため。

@MainActor
enum Actions {
    static func run(_ action: CustomAction, on paths: [String]) {
        guard !paths.isEmpty else {
            NSSound.beep()
            return
        }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        do {
            switch action.kind {
            case .script:
                try runScript(action.value, arguments: paths)
            case .openWith:
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(
                    urls, withApplicationAt: URL(fileURLWithPath: action.value), configuration: config
                ) { _, error in
                    guard let error else { return }
                    Task { @MainActor in report(action, error) }
                }
            case .copyTo:
                try transfer(urls, to: action.value, move: false)
            case .moveTo:
                try transfer(urls, to: action.value, move: true)
            }
        } catch {
            report(action, error)
        }
    }

    /// /bin/zsh -c で走らせ、パスを "$@" で渡す。終わりは待たない
    private static func runScript(_ script: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -c の直後の引数は $0 になる。"$@" に全部入るよう、名前を1つ挟む
        process.arguments = ["-c", script, "ocomenu"] + arguments
        // 右クリックした項目が1つなら、その場所で走らせる。フォルダならその中、ファイルならその親
        if let first = arguments.first {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: first, isDirectory: &isDirectory)
            process.currentDirectoryURL =
                isDirectory.boolValue
                ? URL(fileURLWithPath: first) : URL(fileURLWithPath: first).deletingLastPathComponent()
        }
        try process.run()
    }

    /// 同じ名前があれば「名前 2」にする。Finder と同じ付け方
    private static func transfer(_ urls: [URL], to folder: String, move: Bool) throws {
        let destination = URL(fileURLWithPath: folder, isDirectory: true)
        let manager = FileManager.default
        for url in urls {
            let name = UniqueName.make(for: url.lastPathComponent) {
                manager.fileExists(atPath: destination.appendingPathComponent($0).path)
            }
            let target = destination.appendingPathComponent(name)
            if move {
                try manager.moveItem(at: url, to: target)
            } else {
                try manager.copyItem(at: url, to: target)
            }
        }
    }

    private static func report(_ action: CustomAction, _ error: any Error) {
        log.error("custom item failed: \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = L.actionFailed(action.title)
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
