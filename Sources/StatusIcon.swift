import AppKit

// メニューバーのアイコン。
//
// アプリのアイコンと同じ図柄を、メニューバー用の白黒で描く。メニューの板の縁の中に米粒が3つ並び、
// 真ん中の1粒だけが右へ抜け出している。テンプレート画像にして、メニューバーの明暗に合わせて色を変えさせる。
// 最初は macOS の記号（contextualmenu.and.cursorarrow）を借りていて、本人に「地味」と言われた。

enum StatusIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // メニューの板。右の縁は、抜け出す米粒の高さだけ途切れさせる
            let panel = NSRect(x: 2, y: 1.5, width: 11, height: 15)
            let outline = NSBezierPath(roundedRect: panel, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1.5
            NSGraphicsContext.current?.saveGraphicsState()
            let gap = NSBezierPath(rect: NSRect(x: panel.maxX - 2, y: 7, width: 4, height: 4))
            let clip = NSBezierPath(rect: NSRect(origin: .zero, size: size))
            clip.append(gap)
            clip.windingRule = .evenOdd
            clip.addClip()
            outline.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()

            // 米粒。上と下は板の中、真ん中は右へ抜け出している
            for grain in [
                NSRect(x: 4.5, y: 4, width: 6, height: 2.6),
                NSRect(x: 9.5, y: 7.7, width: 8, height: 2.6),
                NSRect(x: 4.5, y: 11.4, width: 6, height: 2.6),
            ] {
                NSBezierPath(ovalIn: grain).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ocomenu"
        return image
    }
}
