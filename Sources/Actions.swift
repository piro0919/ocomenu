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
                try runScript(action.value, arguments: paths) { outcome, stderr in
                    guard let detail = outcome.message(stderr: stderr) else { return }
                    report(action, detail: detail)
                }
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

    /// /bin/zsh -c で走らせ、パスを "$@" で渡す。終わるのを待たずに戻り、終わったら finished を呼ぶ。
    /// 標準エラーは集めておき、0 以外で終わったときに見せる。黙って失敗させないため
    private static func runScript(
        _ script: String, arguments: [String],
        finished: @escaping @MainActor (ScriptOutcome, String) -> Void
    ) throws {
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

        // 標準エラーは読み続ける。読まずにいると、パイプが一杯になったところでスクリプトが止まる
        let pipe = Pipe()
        let errors = ErrorBuffer(pipe.fileHandleForReading)
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { _ in errors.drain() }
        process.terminationHandler = { process in
            // スクリプトが裏に残した子が標準エラーを握っていても、終わりの知らせは遅らせない。
            // 本体が書いたものはもうパイプの中にあるので、待たずに読み切れる
            pipe.fileHandleForReading.readabilityHandler = nil
            errors.drain()
            let outcome = ScriptOutcome(status: process.terminationStatus, reason: process.terminationReason)
            let text = errors.text
            Task { @MainActor in finished(outcome, text) }
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
        report(action, detail: error.localizedDescription)
    }

    private static func report(_ action: CustomAction, detail: String) {
        log.error("custom item failed: \(detail, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = L.actionFailed(action.title)
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}

/// スクリプトの終わり方
enum ScriptOutcome: Equatable, Sendable {
    case success
    /// 0 以外の終了コードで終わった
    case exited(Int32)
    /// シグナルで止められた
    case signaled(Int32)

    init(status: Int32, reason: Process.TerminationReason) {
        switch reason {
        case .uncaughtSignal: self = .signaled(status)
        default: self = status == 0 ? .success : .exited(status)
        }
    }

    /// 知らせる文。うまく終わったなら nil
    func message(stderr: String) -> String? {
        let status: String
        switch self {
        case .success: return nil
        case .exited(let code): status = L.scriptExited(code)
        case .signaled(let signal): status = L.scriptSignaled(signal)
        }
        let excerpt = Self.excerpt(stderr)
        return excerpt.isEmpty ? status : status + "\n\n" + excerpt
    }

    /// 標準エラーの末尾。長いと警告が画面からはみ出すので、最後のほうだけ見せる。原因はたいてい最後に出る
    static func excerpt(_ text: String, limit: Int = 600) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return "…" + String(trimmed.suffix(limit))
    }
}

/// スクリプトの標準エラーを溜める。読むのはパイプの見張りと終わりの知らせの2か所で、どちらも裏の糸から来る
private final class ErrorBuffer: @unchecked Sendable {
    /// 溜めておく上限。見せるのは末尾だけなので、これを超えたら頭を捨てる
    private static let capacity = 16 * 1024

    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(_ handle: FileHandle) {
        self.handle = handle
        // 読むものが無いときに待たないようにする。終わりの知らせの側で止まらないため
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    /// 今パイプにある分を読み切る。閉じていたら見張りを外す（閉じたパイプは読めると言い続けるため）
    func drain() {
        lock.lock()
        defer { lock.unlock() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(handle.fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
                if data.count > Self.capacity { data.removeFirst(data.count - Self.capacity) }
            } else {
                if count == 0 { handle.readabilityHandler = nil }
                return
            }
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
