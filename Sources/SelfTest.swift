import Foundation

/// 画面を出さずに、計算だけを確かめる。`./Ocomenu --selftest` で走る。
/// 触れるのは値の計算だけで、AX にも Finder にも設定にも触らない。
@MainActor
enum SelfTest {

    private static var failures = 0

    static func run() -> Int32 {
        failures = 0

        // 右クリックの扱い
        do {
            check(
                ClickDecision.decide(onItem: true, selected: false, frontWindow: true, bypass: false) == .select,
                "未選択の項目は Finder に選択させる")
            check(
                ClickDecision.decide(onItem: true, selected: true, frontWindow: true, bypass: false) == .swallow,
                "前面の窓の選択済みの項目は渡さない（複数選択が縮み、名前の変更が始まるため）")
            check(
                ClickDecision.decide(onItem: true, selected: true, frontWindow: false, bypass: false) == .select,
                "裏の窓なら選択済みでも渡し、窓を前に出させる")
            check(
                ClickDecision.decide(onItem: false, selected: false, frontWindow: true, bypass: false) == .pass,
                "項目の上でなければ横取りしない")
            check(
                ClickDecision.decide(onItem: true, selected: true, frontWindow: true, bypass: true) == .pass,
                "⌘ を押していれば元のメニュー")
        }

        // 既定の並び
        do {
            let defaults = MenuLayout.defaults
            let builtins = defaults.compactMap { entry -> BuiltinItem? in
                if case .builtin(let item) = entry.content { return item }
                return nil
            }
            check(Set(builtins) == Set(BuiltinItem.allCases), "既定では標準の項目を全部出す")
            check(builtins.count == BuiltinItem.allCases.count, "既定に同じ項目が2つ無い")
            check(defaults.allSatisfy { !$0.hidden }, "既定では何も隠さない")
            check(defaults.first?.content == .builtin(.open), "先頭は「開く」（Finder と同じ）")
        }

        // 初期状態に戻す
        do {
            let custom = MenuEntry(.custom(CustomAction(kind: .script, title: "T", value: "true")))
            let reset = MenuLayout.reset([MenuEntry(.builtin(.copy)), custom])
            check(reset.contains { $0.id == custom.id && $0.hidden }, "初期状態に戻しても、作った項目は隠して残す")
            check(
                MenuLayout.visible(reset).map(\.content) == MenuLayout.visible(MenuLayout.defaults).map(\.content),
                "初期状態に戻すと、見える並びは既定と同じ")
        }

        // 保存してある並びを直す
        do {
            let saved = [MenuEntry(.builtin(.getInfo)), MenuEntry(.builtin(.getInfo)), MenuEntry(.separator)]
            let fixed = MenuLayout.normalized(saved)
            check(
                fixed.filter { $0.content == .builtin(.getInfo) }.count == 1,
                "同じ標準の項目が2つあれば1つにする")
            check(
                fixed.count == 2 + BuiltinItem.allCases.count - 1,
                "足りない標準の項目を末尾に足す")
            check(MenuLayout.normalized(fixed) == fixed, "直したものをもう一度直しても変わらない（読むたびに保存し直さない）")
            check(
                fixed.dropFirst(2).allSatisfy(\.hidden),
                "後から足した標準の項目は隠しておく（並びを勝手に変えない）")
        }

        // 実際に出す行
        do {
            let entries = [
                MenuEntry(.separator),
                MenuEntry(.builtin(.open)),
                MenuEntry(.separator),
                MenuEntry(.builtin(.rename), hidden: true),
                MenuEntry(.separator),
                MenuEntry(.builtin(.copy)),
                MenuEntry(.separator),
            ]
            let visible = MenuLayout.visible(entries).map(\.content)
            check(
                visible == [.builtin(.open), .separator, .builtin(.copy)],
                "隠したものを抜き、区切り線を先頭・末尾・連続に置かない")
            check(MenuLayout.visible([MenuEntry(.separator)]).isEmpty, "区切り線だけなら空")
        }

        // 保存の形
        do {
            let entries = [
                MenuEntry(.builtin(.share), hidden: true),
                MenuEntry(.custom(CustomAction(kind: .script, title: "Echo", value: "echo \"$@\""))),
                MenuEntry(.separator),
            ]
            let data = try? JSONEncoder().encode(entries)
            let decoded = data.flatMap { try? JSONDecoder().decode([MenuEntry].self, from: $0) }
            check(decoded == entries, "JSON にして戻しても同じ")
        }

        // メニューバーの項目を名前で探す
        do {
            let titles = ["“piro”のパス名をコピー", "コピー", "“fetch.py”を圧縮"]
            check(MenuMatch.index(of: BuiltinItem.copy.names, in: titles) == 1, "完全一致を先に探す")
            check(MenuMatch.index(of: BuiltinItem.copyPath.names, in: titles) == 0, "名前の入る項目は後方で当てる")
            check(MenuMatch.index(of: BuiltinItem.compress.names, in: titles) == 2, "「“名前”を圧縮」を拾う")
            check(
                MenuMatch.index(of: BuiltinItem.compress.names, in: ["Compress “fetch.py”"]) == 0,
                "英語は前方で当てる")
            check(MenuMatch.index(of: BuiltinItem.getInfo.names, in: titles) == nil, "無ければ nil")
        }

        // 行き先で名前がぶつかったとき
        do {
            let taken: Set<String> = ["a.txt", "a 2.txt", "folder"]
            check(UniqueName.make(for: "b.txt", exists: taken.contains) == "b.txt", "空いていればそのまま")
            check(UniqueName.make(for: "a.txt", exists: taken.contains) == "a 3.txt", "拡張子の前に番号を足す")
            check(UniqueName.make(for: "folder", exists: taken.contains) == "folder 2", "拡張子が無ければ末尾に足す")
        }

        // 識別子が被っていないこと
        do {
            let all = BuiltinItem.allCases.flatMap(\.identifiers)
            check(Set(all).count == all.count, "メニューバーの識別子が項目どうしで被らない")
        }

        print(failures == 0 ? "selftest: all passed" : "selftest: \(failures) failed")
        return failures == 0 ? 0 : 1
    }

    private static func check(_ condition: Bool, _ name: String) {
        if condition {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("  NG  \(name)")
        }
    }
}
