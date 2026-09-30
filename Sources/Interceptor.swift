import AppKit

// Finder の右クリックの横取り。
//
// イベントタップで control+クリックと右ボタンを受け、Finder に届く前に止める。
// どう扱うかは ClickDecision が決める。ここは受け渡しと、押してから離すまでの記録だけを持つ。

@MainActor
final class Interceptor {
    static let shared = Interceptor()

    /// 右クリックの行き先が決まったあとに呼ぶ。メニューを出す側が受け取る
    var onMenuRequest: ((_ location: CGPoint, _ window: AXUIElement?) -> Void)?

    private var tap: CFMachPort?

    /// 普通のクリックに直して渡した押下。対になる離しも直して渡し、そのあとでメニューを出す
    private var converted: (location: CGPoint, window: AXUIElement?)?

    var isRunning: Bool { tap != nil }

    /// 自前のメニューを開いている間は真。外のクリックで閉じるのに使う
    var menuIsOpen = false

    /// タップを張る。アクセシビリティの許可が無ければ張れず false
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        var mask: CGEventMask = 0
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp] {
            mask |= CGEventMask(1) << type.rawValue
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    // タップは主の実行ループに載せているので、呼び戻しは主で来る。
                    // CGEvent は Sendable でないので、隔離の外へは「渡すか」だけを持ち出す
                    let passes = MainActor.assumeIsolated { Interceptor.shared.handle(type, event) }
                    return passes ? Unmanaged.passUnretained(event) : nil
                }, userInfo: nil)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        // メニューを開いている間も受けたいので .common に載せる
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    /// その位置にあるのが自前のメニューか
    private func isOwnElement(at point: CGPoint) -> Bool {
        var hit: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(
                AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
            let hit
        else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        return pid == getpid()
    }

    /// 中身を書き換えることはあるが、止めるときだけ false を返す
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let pass = true

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 呼び戻しが遅れると OS に切られる。張り直す
            log.error("event tap was disabled (\(type.rawValue)); re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .leftMouseUp, .rightMouseUp:
            guard let pending = converted else { return pass }
            converted = nil
            event.flags.remove(.maskControl)
            if type == .rightMouseUp {
                event.type = .leftMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
            }
            // Finder が選択し終わるのを待ってから出す。離した後なら、押しっぱなしの状態が残らない
            DispatchQueue.main.async { [weak self] in
                self?.onMenuRequest?(pending.location, pending.window)
            }
            return pass

        case .leftMouseDown, .rightMouseDown:
            // メニューを開いている間に外を押されたら閉じる。Finder の元のメニューと同じく、
            // 普通のクリックは閉じるだけで下へは渡さない。右クリックなら閉じてから、そこで出し直す
            if menuIsOpen, !isOwnElement(at: event.location) {
                ContextMenu.shared.close()
                guard type == .rightMouseDown || event.flags.contains(.maskControl) else { return false }
            }
            guard type == .rightMouseDown || event.flags.contains(.maskControl) else { return pass }
            guard Settings.isEnabled, let element = FinderBridge.finderElement(at: event.location) else {
                return pass
            }
            let hit = FinderBridge.inspect(element)
            let bypass = event.flags.contains(.maskCommand)
            let decision = ClickDecision.decide(
                onItem: hit?.path != nil, selected: hit?.selected ?? false,
                frontWindow: FinderBridge.isFrontWindow(hit?.window), bypass: bypass)

            switch decision {
            case .pass:
                // ⌘ は元のメニューを出すための合図。Finder には ⌘ を付けずに渡す
                if bypass { event.flags.remove(.maskCommand) }
                return pass
            case .swallow:
                let location = event.location
                let window = hit?.window
                DispatchQueue.main.async { [weak self] in
                    self?.onMenuRequest?(location, window)
                }
                return false
            case .select:
                event.flags.remove(.maskControl)
                // 直前のクリックと合わせてダブルクリックとみなされ、項目が開かないようにする
                event.setIntegerValueField(.mouseEventClickState, value: 1)
                if type == .rightMouseDown {
                    event.type = .leftMouseDown
                    event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
                }
                converted = (event.location, hit?.window)
                return pass
            }

        default:
            return pass
        }
    }
}
