import Foundation

// メニューに並べるものの型。
//
// 画面にも AX にも触らない。並びの保存と読み出し、既定の並びだけをここに置く。
// 自己テストから呼ぶので、隔離を持たせない。

/// Finder のメニューバーから押せる標準の項目
enum BuiltinItem: String, CaseIterable, Codable, Sendable {
    case open, openInNewTab, moveToTrash, getInfo, rename, compress, duplicate, makeAlias
    case quickLook, copy, copyPath, share

    /// メニューバーの項目の識別子。言語に依らない。
    /// nib の中の番号なので、macOS の版が変わると変わりうる。そのときは names で探し直す
    var identifiers: [String] {
        switch self {
        case .open: return ["_NS:728"]
        case .openInNewTab: return ["_NS:571"]
        case .moveToTrash: return ["_NS:616"]
        case .getInfo: return ["_NS:715"]
        case .rename: return ["_NS:929"]
        // 「“名前”を圧縮」と「圧縮」の2つがあり、選択によってどちらかが有効になる
        case .compress: return ["_NS:938", "_NS:586"]
        case .duplicate: return ["_NS:695"]
        case .makeAlias: return ["_NS:676"]
        case .quickLook: return ["_NS:577"]
        case .copy: return ["_NS:8"]
        case .copyPath: return ["_NS:956"]
        case .share: return ["_NS:977"]
        }
    }

    /// 識別子で見つからなかったときに探す項目名。まず完全一致で探し、無ければ前方か後方の一致で探す。
    /// 「“名前”を圧縮」「Compress “名前”」のように名前が入るものを拾うため。
    /// 完全一致を先にするのは、「コピー」が「“名前”のパス名をコピー」の後方に一致してしまうため
    var names: [String] {
        switch self {
        case .open: return ["開く", "Open"]
        case .openInNewTab: return ["新規タブで開く", "Open in New Tab"]
        case .moveToTrash: return ["ゴミ箱に入れる", "Move to Trash"]
        case .getInfo: return ["情報を見る", "Get Info"]
        case .rename: return ["名称変更", "Rename"]
        case .compress: return ["圧縮", "Compress"]
        case .duplicate: return ["複製", "Duplicate"]
        case .makeAlias: return ["エイリアスを作成", "Make Alias"]
        case .quickLook: return ["クイックルック", "Quick Look"]
        case .copy: return ["コピー", "Copy"]
        case .copyPath: return ["のパス名をコピー", "as Pathname"]
        case .share: return ["共有…", "Share…"]
        }
    }

    /// どのメニューの下にあるか。日本語と英語の見出し
    var menuTitles: [String] {
        switch self {
        case .copy, .copyPath: return ["編集", "Edit"]
        default: return ["ファイル", "File"]
        }
    }

    var label: String {
        switch self {
        case .open: return L.t("開く", "Open")
        case .openInNewTab: return L.t("新規タブで開く", "Open in New Tab")
        case .moveToTrash: return L.t("ゴミ箱に入れる", "Move to Trash")
        case .getInfo: return L.t("情報を見る", "Get Info")
        case .rename: return L.t("名称変更", "Rename")
        case .compress: return L.t("圧縮", "Compress")
        case .duplicate: return L.t("複製", "Duplicate")
        case .makeAlias: return L.t("エイリアスを作成", "Make Alias")
        case .quickLook: return L.t("クイックルック", "Quick Look")
        case .copy: return L.t("コピー", "Copy")
        case .copyPath: return L.t("パス名をコピー", "Copy as Pathname")
        case .share: return L.t("共有…", "Share…")
        }
    }
}

/// 自分で足す項目
struct CustomAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// シェルスクリプトを実行する。選んだ項目のパスを "$@" で渡す
        case script
        /// 決めたアプリで開く
        case openWith
        /// 決めたフォルダへコピーする
        case copyTo
        /// 決めたフォルダへ移動する
        case moveTo
    }

    var kind: Kind
    var title: String
    /// script ならスクリプトの本文、openWith ならアプリのパス、copyTo / moveTo なら行き先のフォルダ
    var value: String
}

/// メニューの1行
struct MenuEntry: Codable, Equatable, Identifiable, Sendable {
    enum Content: Codable, Equatable, Sendable {
        case builtin(BuiltinItem)
        case custom(CustomAction)
        case separator
    }

    var id: UUID
    var content: Content
    /// 標準の項目は消しても配列に残し、印だけ付ける。消したものを戻す場所が要るため
    var hidden: Bool

    init(id: UUID = UUID(), _ content: Content, hidden: Bool = false) {
        self.id = id
        self.content = content
        self.hidden = hidden
    }
}

enum MenuLayout {
    /// 入れた直後の並び。Finder の右クリックと同じ順で、標準の項目を全部出す。
    /// 入れただけで何かが消えることはない
    static var defaults: [MenuEntry] {
        let groups: [[BuiltinItem]] = [
            [.open, .openInNewTab],
            [.moveToTrash],
            [.getInfo, .rename, .compress, .duplicate, .makeAlias, .quickLook],
            [.copy, .copyPath, .share],
        ]
        var entries: [MenuEntry] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { entries.append(MenuEntry(.separator)) }
            entries += group.map { MenuEntry(.builtin($0)) }
        }
        return entries
    }

    /// 保存してある並びを直す。後の版で標準の項目が増えたら、隠した状態で末尾に足す。
    /// 並びを勝手に変えないため、出すのは利用者に任せる
    static func normalized(_ entries: [MenuEntry]) -> [MenuEntry] {
        var result: [MenuEntry] = []
        var seen = Set<BuiltinItem>()
        for entry in entries {
            if case .builtin(let item) = entry.content {
                // 同じ標準の項目が2つあれば後ろを捨てる
                guard seen.insert(item).inserted else { continue }
            }
            result.append(entry)
        }
        for item in BuiltinItem.allCases where !seen.contains(item) {
            result.append(MenuEntry(.builtin(item), hidden: true))
        }
        return result
    }

    /// 実際に出す行。隠したものを抜き、区切り線が先頭・末尾・連続に来ないように詰める
    static func visible(_ entries: [MenuEntry]) -> [MenuEntry] {
        var result: [MenuEntry] = []
        for entry in entries where !entry.hidden {
            if entry.content == .separator {
                guard let last = result.last, last.content != .separator else { continue }
            }
            result.append(entry)
        }
        while result.last?.content == .separator { result.removeLast() }
        return result
    }
}

/// コピー・移動の行き先で名前がぶつかったときの名前。Finder と同じく「名前 2.拡張子」とする
enum UniqueName {
    static func make(for name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !exists(candidate) { return candidate }
            number += 1
        }
    }
}

/// 名前でメニュー項目を探すときの当て方。完全一致を先に、無ければ前方か後方の一致
enum MenuMatch {
    static func index(of names: [String], in titles: [String]) -> Int? {
        if let exact = titles.firstIndex(where: { names.contains($0) }) { return exact }
        return titles.firstIndex { title in
            names.contains { title.hasPrefix($0) || title.hasSuffix($0) }
        }
    }
}

/// 右クリックをどう扱うか
enum ClickDecision: Equatable, Sendable {
    /// 触らずに Finder へ渡す。Finder の元のメニューが出る
    case pass
    /// Finder へ渡さず、そのまま自前のメニューを出す
    case swallow
    /// control を外した普通のクリックとして渡し、Finder に選択させてから自前のメニューを出す
    case select

    /// - Parameters:
    ///   - onItem: カーソルの下にファイルやフォルダがあるか
    ///   - selected: その項目が選択済みか
    ///   - frontWindow: その項目の窓が Finder の前面の窓か
    ///   - bypass: 元のメニューを出す修飾キー（⌘）が押されているか
    static func decide(onItem: Bool, selected: Bool, frontWindow: Bool, bypass: Bool) -> ClickDecision {
        if bypass || !onItem { return .pass }
        // 選択済みの項目を普通のクリックとして渡すと、複数選択が1つに縮み、
        // 少し置いて名前の変更が始まる。渡さない。
        // ただし裏の窓なら渡す。メニューバーの項目は前面の窓に対して働くので、窓を前に出させる必要がある
        return selected && frontWindow ? .swallow : .select
    }
}
